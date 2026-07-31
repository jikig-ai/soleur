---
title: "Art. 30(1) entries for the Anthropic-egressing Inngest fleet and the claude-code-action CI surface"
type: docs
issue: 7100
closes: 7100
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-31
---

# docs(legal): register the claude-eval cron fleet and the claude-code-action CI surface in the Art. 30 record

> **DRAFT — planning artifact. The legal artifacts this plan produces are themselves drafts requiring professional legal review.**

## Overview

`knowledge-base/legal/article-30-register.md` carries PA-1 … PA-30 and its §0 declares
`jikig-ai/soleur` an in-scope surface — yet **no entry covers the dominant Jikigai-keyed
Anthropic egress surface at all**. Counsel review
`knowledge-base/legal/audits/2026-07-counsel-review-7086.md` § Finding 1 calls this
"a live Art. 30(1) incompleteness, not a stylistic one", and § Finding 2 deferred the fix
with disposition "record + track. Do not author the PA here." This plan is that
authoring work. PR #7086 amended `anthropic.md` and `compliance-posture.md` and left
INCOMPLETE markers pointing at **#7100**; it did not touch the register.

The downstream records describe the gap as two things ("the fleet **or** the active CI
surface"). Legal review established it is **three**, because publication is a distinct
operation under Art. 4(2) and cannot share a `(d)` recipients cell or an `(f)` retention cell
with internal egress — see **D1**. The two halves as the issue frames them:

1. **A scheduled Inngest fleet** — 15 cron functions that transmit repository and community
   content to the Anthropic API under the operator's own first-party `ANTHROPIC_API_KEY`,
   plus 3 HTTP callers and 3 non-cron modules on the same substrate. Jikigai is
   **controller**; Anthropic is an Art. 28 **processor**. This is *not* the
   BYOK independent-controller carve-out at register §0.
2. **A `pull_request`-triggered CI workflow** — `.github/workflows/fix-constraints-stage-a.yml`,
   workflow-state **active**, which runs `anthropics/claude-code-action` over the PR-head
   tree with `secrets.ANTHROPIC_API_KEY`.

Two findings from the counsel review are load-bearing and must survive into the records:

- **Output minimization is not input minimization.** `cron-community-monitor`'s directives
  constrain the digest *output*; the raw Discord messages, GitHub comment bodies and HN
  comment text are in the model *input* regardless.
- **The Anthropic DPA row cannot supply a lawful basis.** It is an Art. 28 vendor record;
  lawful basis is a controller-side Art. 6 determination that lives in the PA. Art. 28
  coverage is unaffected — the DPA auto-incorporates via Commercial Terms §C at the
  account level, not per-workload.

**This PR is docs-only under `knowledge-base/legal/**`.** It records the system as it is.
Every code-side remediation it identifies is deferred to a tracked follow-up issue created
during this PR's lifecycle.

**Read `## Decision Challenges` before starting.** Review raised four challenges, two of them
to the docs-only scope itself, and one substantive consequence the operator must see: the
honest record will state that a **live, five-month-old, materialised** limb of the processing
has **no available lawful basis** (D9). That is not a drafting choice — asserting a basis the
processing does not have is precisely the defect #7100 exists to fix.

## Research Reconciliation — claims vs. verified reality

Every number in the issue body, in the counsel review's "Claims verified as ACCURATE"
list, and in the two amended legal records is a claim. I re-derived each. **Where the
verified value differs, the verified value is authoritative and the plan corrects the
downstream records rather than propagating the error.**

| Claim (source) | Verified reality | Plan response |
|---|---|---|
| "15 crons call `spawnClaudeEval`" (issue; `anthropic.md` 2026-07-30 bullet; audit § Claims verified) | **13** cron files call `spawnClaudeEval`. `cron-daily-triage.ts:241` and `cron-follow-through-monitor.ts:520` call `spawn(resolveClaudeBin(), …)` **directly**, bypassing the helper. "15 crons egress to Anthropic via the CLI" IS correct. | Scope PA-31 by **egress**, not by helper name (D2). Record both figures with anchors. Correct the `anthropic.md` bullet. |
| "17 files import the substrate; 2 for types/constants only" | **20** modules carry a real `from "./_cron-claude-eval-substrate"` import/export. **1** is type-only (`_cron-shared.ts`, `import type { SpawnResult }`); **1** uses only workspace helpers and invokes no Claude (`cron-skill-freshness.ts`, whose header states "I2 — Trivially satisfied: no claude"). `cron-workspace-gc.ts` names the substrate **in a comment only** and is not an importer. | Correct the enumeration in `anthropic.md`. Do not restate "17/2". |
| "2 HTTP crons on `postAnthropicMessage`" | **3**: `cron-compound-promote.ts:589`, `cron-weekly-release-digest.ts:259`, **and `cron-anthropic-credit-probe.ts:83`** — an hourly `maxTokens: 1` literal `"ping"`. | Enumerate all three; record the credit probe as **nil personal data**. The failure mode being fixed is non-exhaustive enumeration, so a nil-PII member is still named. |
| "the active `claude-code-action` CI surface" (singular) | **Five** `.github/` files supply `secrets.ANTHROPIC_API_KEY` (measured 2026-07-31). Only **three** use `claude-code-action`, and one of those is `disabled_manually`. Two live callers — `ci.yml`'s `sandbox-canary-capture-gate` and `plugin-root-propagation-gate` — reach Anthropic via a step-level `env:` with **no** `claude-code-action` involved, on `push:[main]` + `pull_request` + `merge_group`. | A PA-33 scoped to "workflows using `claude-code-action`" would be **false on the day it is written**. Key membership on the **secret reference** (D8). Full table at AC11g. |
| Learnings research: anchor ACs on `^- PA-31` | The register has **no `- PA-N` bullet form**. Headings are `## Processing Activity N — <title>`; "PA-N" appears only in cross-references. | Anchor every AC on `^## Processing Activity 31 — `. |
| Learnings research: "the Art. 30 register has an Eleventy mirror" | It does not. Only the nine `docs/legal/*.md` files have mirrors under `plugins/soleur/docs/pages/legal/`. The register is an internal record. | No mirror edit for the register. Mirror duty applies only if Privacy Policy is touched (see D5). |
| External research: "EDPB Guidelines 03/2026 … newly finalized (July 2026)" | **Adopted 8 July 2026 for PUBLIC CONSULTATION, open until 30 October 2026** (verified against `edpb.europa.eu`). It is a **consultation draft**, not settled guidance. | Cite as a draft in consultation, with the closing date, and add final adoption as a re-evaluation trigger. **Never cite it as settled law.** |
| External research: "Discord membership / GitHub contributor identity are sensitive categories" | These are **not** Art. 9 special categories. | Do not import this error. The Art. 9 cell reasons from the actual content risk (free text may contain anything), not from a miscategorisation. |
| External research: "large-scale processing (15+ data sources daily)" | WP243/WP248 "large scale" turns on number of data subjects, data volume, duration and geographic extent — **not source count**. | The DPIA memo must reason the criterion honestly rather than adopt the agent's framing. |
| Repo research: SHA constant at `src/legal-doc-shas.ts` | It is `apps/web-platform/lib/legal/legal-doc-shas.ts` (per the import in `apps/web-platform/test/legal-doc-shas-guard.test.ts`). | Cite the correct path in the deferred-issue body. |
| Issue premise: #7100 is live, un-duplicated follow-on | `gh issue view 7100` → **OPEN**, `closedByPullRequestsReferences: []`. PR #7086 **MERGED** 2026-07-30, touching `anthropic.md`, `compliance-posture.md` and the audit — **not** `article-30-register.md`. | Premise holds. Designated follow-on, not a duplicate. |

**Premise Validation.** All referenced artifacts confirmed present on this worktree:
`article-30-register.md` (611 lines, PA-30 heading at the `## Processing Activity 30 — Owner-private beta-tester / prospect CRM` anchor, closing `---`, then `## Register Maintenance`);
`2026-07-counsel-review-7086.md`; `anthropic.md` (INCOMPLETE marker on the
`register_activity_refs:` line); `compliance-posture.md` (the `#7100` parenthetical inside
the Anthropic PBC vendor row); the four named source files; the workflow. The register
contains **zero** occurrences of `7100` — no placeholder exists.

## User-Brand Impact

**If this lands broken, the user experiences:** a Discord member, Hacker News poster or
GitHub commenter finds their handle — and up to 120 characters of their own comment — in a
world-readable daily digest committed permanently to `jikig-ai/soleur`, asks Jikigai on
what basis their data was sent to a US LLM provider and republished, and the Art. 30
register still has no answer. A wrong or over-claiming record is worse than the current
honest silence: it converts an incompleteness into a misstatement to a supervisory
authority.

**If this leaks, the user's data is exposed via:** this PR opens no new data flow — it
records existing ones. The vectors it must describe accurately are (i) raw Discord guild
messages, GitHub comment bodies and full HN comment text reaching Anthropic under an
**unsigned** Zero-Retention amendment, so the default **30-day** API retention applies, and
(ii) third-party handles plus comment snippets published to a permanent public git history
with **no erasure routine**.

**Brand-survival threshold:** `single-user incident`. One community member, one complaint,
one CNIL contact. Accordingly `requires_cpo_signoff: true`, and `user-impact-reviewer`
runs at review time.

## Design Decisions

Each decision is recorded with its rationale and the alternative that was rejected, so
review can contest the choice rather than reverse-engineer it.

### D1 — THREE register entries, organised by the public-output operation *(revised on CLO review)*

**Decision.**

| Entry | Scope | Public output? |
|---|---|---|
| `## Processing Activity 31 — Anthropic-egressing Inngest function fleet (#7100)` | The fleet's repo/engineering population; internal egress to Anthropic only | No |
| `## Processing Activity 32 — Community observation and republication (#7100)` | `cron-community-monitor` (sub-purpose i) **and `cron-daily-triage`'s public-issue-comment limb** (sub-purpose ii) | **Yes** |
| `## Processing Activity 33 — Jikigai-keyed Anthropic API surface in GitHub Actions CI (#7100)` | The five `.github/` members carrying `secrets.ANTHROPIC_API_KEY` | No |

**Why three, not two.** The plan's first draft split on purpose and data subjects, then
failed to apply that principle consistently. CLO review showed the two-entry split is
**under-split by its own rationale**, because two cells cannot be reconciled in one row:

- **`(d)` recipients.** PA-31's is "Anthropic PBC". PA-32's must read "**the general public**
  (world-readable git repository and public GitHub issues), and GitHub Inc as host of that
  public surface." That *inverts* PA-17's framing, where GitHub is expressly "the **source**
  (not recipient)". One row cannot hold both.
- **`(f)` retention.** PA-31's is "30 days at the processor". PA-32's is "**permanent; no
  erasure routine exists; 2 forks**". These are not variants of one envelope.

Under Art. 4(2) publication is a distinct operation ("disclosure by transmission,
dissemination or otherwise making available"). The organising principle is therefore **the
public-output operation, not the cron's identity** — which is why `cron-daily-triage` sits in
PA-32 despite being a fleet member: its `gh issue comment` writes third-party content to a
public surface. PA-17's `(b)(i)/(b)(ii)` sub-purpose form is the register's own precedent.

**Titles.** "cron fleet" mis-describes three of PA-31's 21 members (one merge-event function,
two transient one-shots); "claude-code-action CI" mis-describes PA-33's true membership (D8).
`scripts/check-pa-22.sh` baseline verified green 2026-07-31 before any edit (AC11i).

### D9 — Art. 6(1)(f) is NOT available for the republication limb as implemented *(CLO)*

**This is the plan's most consequential finding and it changes what the record must say.**

The republication limb is not a prospective risk to describe. It is **materialised, at scale,
and partly live today** (verified by CLO against the repo):

- **80 digests**, `2026-02-19` → `2026-06-08`, in `knowledge-base/support/community/`, on a
  **public** repo with **2 forks** (`gh repo view` → `{"forkCount":2,"isPrivate":false}`).
  Committed by `claude[bot]` (73) and `soleur-ai[bot]` (5) under auto-merge — **no human gate**.
- **45 files** carry the `| User | Issue/PR | Comment |` table; **65** reference stargazers by
  username and date.
- Named Discord members with handles, real first names, join dates and inferred affiliation.
- A **verbatim quoted private-guild message attributed to a handle, disclosing the speaker's
  employer context**.
- **Zero deletions ever** — `git log --diff-filter=D -- knowledge-base/support/community/`
  returns 0 commits.

**Planner re-verification, 2026-07-31.** Every figure above was independently re-measured;
all reproduced **except the commenter-table count, which is 45, not the 46 first reported**.
That one-off discrepancy is itself the argument for the Phase 0.1 rule: figures in a legal
record are measured at authoring time, never inherited — including from this plan.

```bash
ls knowledge-base/support/community/*-digest.md | wc -l                          # 80
grep -l '| User | Issue/PR | Comment |' knowledge-base/support/community/*.md | wc -l  # 45
grep -li 'stargazer' knowledge-base/support/community/*.md | wc -l               # 65
git log --oneline --diff-filter=D -- knowledge-base/support/community/ | wc -l   #  0
```
- The **public-issue limb is live now** (#7030, #7051, #7052, #7075, 2026-07-28..30), while
  the file-write limb appears to have been broken since 2026-06-08 — #7075 links a digest file
  that does not exist. Re-verify that state at merge; it reduces nothing legally.

**Necessity fails, and it is dispositive.** The digest's purpose is operator awareness of
community activity. Naming the stargazer, naming and quoting the Discord member, and
tabulating commenter handles with snippets is **not necessary** to that purpose — an aggregate
count plus a link to the source issue serves it identically. Art. 6(1)(f)'s necessity limb is
strict (C-13/16 *Rīgas satiksme*; EDPB Guidelines 1/2024): where a less intrusive means
achieves the purpose, LI is unavailable **regardless of how the balancing would come out**.

**Balancing would fail anyway on the Discord arm.** The guild is bot-token-gated. A member's
Recital 47 reasonable expectation is that their message stays in the guild — not that it is
quoted verbatim, attributed, and committed to a world-readable repository.

**Art. 17 is not merely unimplemented — it is not implementable.** Git history is append-only.
Deleting a digest in a new commit erases nothing: the data persists in every prior commit
object, in GitHub's commit UI, in every clone, and in **both forks**. `filter-repo` +
force-push breaks downstream clones, **does not reach forks**, and does not reach public issue
bodies (GitHub retains issue edit history).

**The decisive internal precedent: Jikigai has already decided this question against itself.**
PA-30's lawful-basis analysis justifies the beta-CRM's structured store over *"git-committed
PII, an Art. 17 impossibility"*
(`knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md`).
`cron-community-monitor` does precisely the thing Jikigai rejected in writing for a different
activity — on a *public* repo rather than a private table. A supervisory authority reading
both entries finds the inconsistency immediately.

**Consequence for this PR.** The honest conclusion for PA-32's republication limb, as
implemented, is **"legitimate interest does not prevail"** — that limb should be minimised or
cease. The record must say so. Recording Art. 14 as an honest gap (D5) while asserting a clean
Art. 6(1)(f) basis for republication would be the fabricated-assessment failure mode, not an
honest gap record.

**Remediations R1–R5** (R1–R3 are prompt-string edits; R4 is a small handler-side function):

| | Remediation | Rationale |
|---|---|---|
| R1 | Drop the mandated stargazer username list → aggregate count | Removes the largest identifier volume |
| R2 | Replace the `\| User \| Issue/PR \| Comment \|` table with issue link + count | Removes handles + snippets |
| R3 | Move the aggregate-only directive out of the LinkedIn paragraph to digest scope; delete "Brief contextual quotes … with attribution are acceptable" | Kills attributed quotation of semi-private Discord and HN content |
| R4 | **Code-level** redaction pass over the digest file and issue body before persistence | PA-27's own DPIA residual (a) says *"a prompt instruction is a claim, not a mechanism"* — with more force here, since there is no output allowlist and there **is** a publication tool |
| R5 | A retention/erasure posture for published artifacts, or an explicit finding that none is possible and the data must therefore not be published | Art. 5(1)(e) + Art. 17 |

These are source edits, outside this PR's docs-only scope — see **UC-3** in
`## Decision Challenges`. The plan's disposition: **record the conclusion honestly in PA-32
and file R1–R5 as a single blocking remediation issue**, because a record that names an
unavailable lawful basis and tracks the fix is defensible, whereas one that asserts a basis it
does not have is not.

### D2 — Scope PA-31 by an egress predicate, not by the helper name

**Decision.** Scope by **credential and transport**, with content categories stated as a
*property of members* rather than as the membership criterion, followed by a **dated member
snapshot table**. Revised per D8 — the first draft's "transmits repository or community
content" was a content test no grep can run, and it misclassified a member at commit time.

> **Scope predicate (PA-31).** Every Inngest function module in
> `apps/web-platform/server/inngest/functions/` matching `{cron,oneshot,event}-*.ts` that
> reaches the Anthropic API under the Jikigai-controlled `ANTHROPIC_API_KEY` — whether by
> spawning the Claude Code CLI (`spawnClaudeEval`, or an inline spawn via
> `resolveClaudeBin`) or by direct HTTPS call to `api.anthropic.com/v1/messages`
> (`postAnthropicMessage`).
>
> **Deliberately outside this predicate**, each recorded elsewhere or for a stated reason:
> (i) `agent-on-spawn-requested` — operator-BYOK key, not Jikigai-keyed → **PA-22**;
> (ii) `cron-anthropic-cost-report` — reads org-billing aggregates from the Anthropic Admin
> API under `ANTHROPIC_ADMIN_KEY`; transmits no repository, community or personal data;
> (iii) GitHub Actions workflows using the same Jikigai key → **PA-33**;
> (iv) `cron-skill-freshness` — clones the repository via the shared substrate helpers but
> invokes no Anthropic call.

**Why this predicate.** Two independent greps agree **byte-for-byte** on the member set
(21 files): `/ANTHROPIC_API_KEY/` and
`/spawnClaudeEval\s*\(|resolveClaudeBin\s*\(|postAnthropicMessage\s*\(/`, both after comment
stripping. Substrate-importers alone is **over**-inclusive (catches `cron-skill-freshness`
and the comment-only `cron-workspace-gc`); `spawnClaudeEval` callers alone is
**under**-inclusive (misses the two direct spawners). Those two wrong predicates are exactly
the two halves of the inherited error.

**Named residual.** No mechanical guard ties the code fleet to the register, so the snapshot
decays. The `(g)` tail names this as an accepted residual and cites the deferred issue —
**but see the User-Challenge in `## Decision Challenges`**: the CTO assesses this residual
as not defensible, because the cheapest correct guard is ~40 lines and the repo already
contains the counter-example (`scripts/check-pa-22.sh`, written with a tracked intent and
never wired, dead since authored).

### D3 — One LIA, three balancing arms

**Decision.** `knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md`,
with the Art. 14 analysis as a section inside it (the `2026-07-07-beta-crm-lia.md`
"### Art. 14 transparency for involuntary data subjects" and `2026-06-15-outbound-email-authority-lia.md`
precedent). Arms:

- **Arm A — repo/engineering population.** Commit authors, issue/PR authors whose content
  is already published in the public repo. Closest precedent is PA-22's reasonable-expectation
  analysis for third-party contributor PII in PR diffs.
- **Arm B — community population.** Discord guild members (**semi-private**: readable only
  with `DISCORD_BOT_TOKEN`, the one non-public source), HN posters, GitHub
  commenters/stargazers. This arm must separately balance the **republication** operation —
  writing handles + snippets to a permanent public surface is a distinct processing
  operation from reading them into a model context, and per the EDPB legitimate-interests
  guidance a new context requires fresh balancing.
- **Arm C — CI contributors.** Same-repo PR authors whose source and PR metadata reach
  Anthropic; forks excluded by the keyless preflight.

**PA-17 trigger.** PA-17's `Lawful basis` cell closes with the "first
third-party-personal-data repository" re-evaluation trigger recorded in the #4558 counsel
review, which re-opens the balancing for natural persons who are neither Owner nor
Co-Member. Arm B **is** that population, so the trigger has fired. The LIA must state that
explicitly and record how it is honoured; whether PA-17 itself must also be amended is a
CLO question flagged in `## Domain Review`.

### D4 — One DPIA screening memo, conclusion NOT prejudged

**Decision.** `knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`,
structured like `2026-06-11-dpia-screening-operator-inbox-triage.md`: frontmatter
(`type: dpia-screening-memo`), the DRAFT blockquote, then
`## 1. Screening against the Art. 35(3) indicators and WP29/EDPB criteria` with a
`| Criterion | Finding |` table over Art. 35(3)(a)–(c) and the WP248 rev.01 nine criteria,
plus a CNIL-list check (France is the supervisory jurisdiction), then named accepted
residuals, then pinned re-screening triggers.

**The conclusion is an output of the assessment, not an input to it.** PA-27 concluded
"no full DPIA at single-operator scale" with **two** WP248 criteria partially engaged. This
activity plausibly engages more: involuntary data subjects; innovative technology; data
from publicly accessible sources; a semi-private source; **republication to a public
surface with no erasure routine**; and a third-country transfer. The memo must run the
criteria honestly and **may** conclude differently from PA-27.

- **Arm (i) — screening suffices.** Memo concludes no full DPIA at current scale, names the
  residuals, pins the triggers. PA-31 / PA-32 / PA-33 `(g)` tails cite it. Plan completes as written.
- **Arm (ii) — full DPIA indicated.** The memo says so, the PAs record `DPIA status: full
  DPIA required — scoped in <issue>`, and the DPIA itself is a tracked follow-up (it is a
  substantially larger artifact than this PR). **Arm (ii) is an acceptable, non-blocking
  outcome.** Writing "no DPIA required" because the precedent said so would be authoring
  the answer before doing the assessment.

### D5 — Art. 14 is ENGAGED, UNDISCHARGED and **OVERDUE** *(reframed on CLO review)*

**Decision.** Record the obligation as **overdue and accruing**, with a tracked multi-channel
remediation. Do **not** assert an Art. 14(5)(b) discharge — and do **not** assume a single
Privacy Policy section would provide one.

**Two corrections from CLO review.** The first draft treated Art. 14 as prospective. It is
not: Art. 14(3)(a) requires the information within one month of obtaining, the earliest
committed digest is `knowledge-base/support/community/2026-02-19-digest.md`, so the obligation
has been unmet since **approximately 2026-03-19** and accrues on each daily run via the live
public-issue limb. "Recorded as open" understates it exactly as "framing not yet assessed"
understated the Art. 30 gap in counsel review #7086 Finding 1.

Second, **a blanket Art. 14(5)(b) claim is not available**, so the remediation is
multi-channel rather than one Privacy Policy section:

| Population | 14(5)(b) disproportionate effort? |
|---|---|
| Discord guild members | **Fails.** Jikigai *operates the guild* — a pinned notice or server-description line costs nothing. |
| GitHub commenters | **Fails.** Reachable via the repo's own README / CONTRIBUTING / issue templates, and by @-mention. |
| Hacker News posters, drive-by stargazers | Arguable — this is the only population for which the exemption is genuinely in play. |

**Wording the PA cell.** The cell must state that the obligation is **unmet**, name the date
from which, and state that **no Art. 14(5) exemption is claimed** — 14(5)(a) unavailable,
14(5)(b) not established for two of the three populations. It is the controller's record that
the obligation is outstanding, not an assertion of compliance. CLO supplied draft wording;
`/work` should adopt it substantially verbatim.

**Why the notice is still not in this PR.** Adding Privacy Policy §4.15 drags in the Eleventy
mirror (guarded by `apps/web-platform/test/legal-doc-consistency.test.ts`) and
`apps/web-platform/lib/legal/legal-doc-shas.ts`, a TypeScript constant pinned by the
`tc-document-sha-guard` CI job — source, outside scope. No `TC_VERSION` bump is required:
`knowledge-base/legal/tc-version-bump-policy.md` governs `terms-and-conditions.md` only, so no
forced user re-acceptance. **But see UC-3** — the same files carry an *affirmatively false*
statement today, which is a stronger reason to widen scope than the notice alone.

**Rationale.** Privacy Policy §4.13 carries an Art. 14(5)(b) public notice for inbound email
senders and §4.14 for outbound recipients. **There is no notice for community-sourced data
subjects.** Art. 14(5)(b) requires the controller to make the information *publicly
available*; the EDPB's draft web-scraping guidance (in consultation until 30 Oct 2026)
reads the exemption narrowly and treats published notice as a condition of invoking it, not
a substitute for it. Asserting a discharge that rests on a notice that does not exist would
be a fresh instance of the exact defect class the counsel review found — a record claiming
a compliance state the system does not have.

**Why the notice is not in this PR.** Adding Privacy Policy §4.15 drags in
`plugins/soleur/docs/pages/legal/privacy-policy.md` (the Eleventy mirror, guarded by
`apps/web-platform/test/legal-doc-consistency.test.ts` heading-sequence parity) **and**
`apps/web-platform/lib/legal/legal-doc-shas.ts` (a TypeScript constant pinned by the
`tc-document-sha-guard` CI job) — a source file, outside this PR's docs-only scope. No
`TC_VERSION` bump is required: `knowledge-base/legal/tc-version-bump-policy.md` governs
`terms-and-conditions.md` only, so no forced user re-acceptance is triggered.

**Wording the PA cell.** The `(b)` cell must state the obligation, that it is undischarged,
the tracked issue, and the target — not hedge it into ambiguity. CLO input governs the
exact phrasing (see `## Domain Review`).

### D8 — Corrections from the CTO review (each would have put a false statement in the record)

The Phase 2.5 engineering review re-ran every grep independently, reproduced the three
corrected counts, and then found **five further defects in this plan's own framing**. Each
becomes a Phase 3 requirement.

- **🔴 Two of the fifteen CLI crons have NO containment hook at all.**
  `cron-daily-triage.ts` and `cron-follow-through-monitor.ts` never call
  `setupEphemeralWorkspace`, so they get **no** `.claude/settings.json`, **no** `PreToolUse`
  hook registration, **no** `CRON_BASH_ALLOWLISTS` entry, and **no** `runHookSelfTest`
  fail-closed spawn probe. They run from the prod container CWD (`/app`), not an ephemeral
  clone — `cron-daily-triage.ts` says so outright: *"This cron never clones, so `gh` runs
  from the prod container CWD /app (no .git)"*. Their only tool control is their own
  `--allowedTools` string, and the substrate's own committed Phase-0 probe evidence records
  that this is **not** a containment boundary: *"headless `claude --print` does NOT
  fail-close non-allowlisted commands via `--allowedTools`/`defaultMode` — only an explicit
  `permissions.deny` rule OR a PreToolUse hook blocks, and an unhooked tool class / a
  crashed hook FAILS OPEN."*
  **Independently re-verified by the planner, 2026-07-31** — partitioning the 15 CLI crons
  on `setupEphemeralWorkspace(` returns exactly **13 hooked / 2 unhooked**, the two being
  `cron-daily-triage.ts` and `cron-follow-through-monitor.ts`:

  ```bash
  D=apps/web-platform/server/inngest/functions
  for f in $({ grep -lE 'spawnClaudeEval\(\{' "$D"/cron-*.ts
               grep -lE 'resolveClaudeBin\(\)'  "$D"/cron-*.ts; } | sort -u); do
    grep -q 'setupEphemeralWorkspace(' "$f" && echo "HOOKED   $f" || echo "UNHOOKED $f"
  done
  ```

  **Consequence:** any PA-31 sentence of the form "each fleet member executes under a
  deny-by-default command allowlist" is false for 2 of 15 — and false in the direction that
  flatters the controller. `(g)` must scope the TOM to the members that actually have it and
  name the two exceptions with their sole compensating control (the Tier-2 nftables egress
  firewall). Whether those two run under the CLI's own sandbox is **not determinable from
  source**; the record must not assert it in either direction.
- **🔴 No PII scrub exists on the Anthropic-bound content in this fleet.** PA-22's TOM
  records `sanitizePromptString` + email scrubbing at prompt assembly. **That measure does
  not exist on the PA-31 path**, and on the CLI path it structurally could not — the agent
  reads files itself, after spawn, under its own `Read`/`Glob`/`Grep` grants.
  `redactGithubSourcedText` is applied only to the outbound Sentry tail. **Copying PA-22's
  TOM into PA-31 would be a materially false Art. 32 statement.** Do not inherit it.
- **A fourth Anthropic-egressing cron this plan had not named.**
  `cron-anthropic-cost-report.ts` dials `api.anthropic.com/v1/organizations/cost_report`
  under **`ANTHROPIC_ADMIN_KEY`** — a different credential, receiving org-billing
  aggregates rather than transmitting content. The predicate correctly excludes it, but the
  record must name it as a **deliberate exclusion with its reason**, or the next reader
  re-runs the grep, finds a fifth Anthropic-dialling cron, and concludes the register is
  incomplete again.
- **The D2 predicate misclassifies a member at commit time.**
  "transmits repository or community content" is a content test no grep can run, and it
  excludes `cron-anthropic-credit-probe` (payload: the literal `"ping"`) while the snapshot
  table includes it — the exact predicate/snapshot divergence the record exists to prevent.
  **Fix:** key membership on the **credential and transport**, and state content categories
  as a *property of members*, not as the membership criterion. Revised predicate in D2 below.
- **PA-33's framing is false on the day it would be written.** `.github/workflows/ci.yml`
  supplies `secrets.ANTHROPIC_API_KEY` to **two further `pull_request`-triggered jobs** that
  are not `claude-code-action` — `sandbox-canary-capture-gate` and
  `plugin-root-propagation-gate` (the latter's own comment: *"Creds-gated (one paid Haiku
  turn)"*). Both are live paid Anthropic calls on same-repo PRs. **PA-32 must key on the
  presence of `secrets.ANTHROPIC_API_KEY`, not on the action used** — a two-line grep
  (`grep -rl 'secrets.ANTHROPIC_API_KEY' .github/`) that survives action renames and the
  eventual replacement of `claude-code-action`. The action becomes a per-member attribute.
  Also name `.github/actions/anthropic-preflight/action.yml` once as the shared
  credential-liveness probe rather than three times.
- **Title the entry for what it is.** `event-ship-merge.ts` is merge-event-triggered and the
  two `oneshot-*` modules are transient — "cron fleet" mis-describes three of the 21
  members. Use **"Anthropic-egressing Inngest function fleet"**.
- **Weaker-than-they-look measures to record with qualification:** teardown is **fail-open**
  (`rm` wrapped in try/catch → Sentry → return), so "workspace destroyed at run end"
  over-claims; credential minimisation is **relative** (most members receive 4–6 env vars,
  `cron-community-monitor` receives **18**, including 14 platform secrets) — give the range
  rather than implying a small number; and allowlist entries justified in-source by "the
  prompt forbids X" are **organisational** measures at best, never technical ones.
- **Genuinely strong, and worth recording as Art. 32 TOMs:** fail-closed-by-construction at
  four independent points in the hook; the spawn-time `runHookSelfTest` that aborts the run;
  the per-cron explicit env allowlist; the ephemeral per-run workspace with a GC backstop;
  the Tier-2 nftables egress restriction (strongest — enforced outside the agent's process
  tree entirely); and secret-path/argument-injection denial applied even when the leading
  verb is allowlisted.
- **`scripts/check-pa-22.sh` is a dead sentinel that this PR's own edit can silently
  break.** It is wired into **no** workflow (`git grep check-pa-22 .github/` → zero hits)
  despite a spec task claiming otherwise, and it asserts a single line matching
  `Anthropic.*PA-22.*autonomous` in the Vendor Mapping row — the exact row Phase 3 rewrites.
  If the rewrite reorders those tokens the script breaks and nothing goes red. Wire it or
  delete it; do not leave a third dead sentinel. Tracked as a deferred item, and Phase 3
  must preserve the token order in the meantime.

### D7 — Recipients and populations the first draft of this plan under-recorded

Surfaced by the Phase 2.7 `gdpr-gate` pass against the plan prose. Each is a limb the
planned record would have got wrong, so each becomes a Phase 3 requirement.

- **`GDPR-Chapter-V` — GitHub Inc is an unrecorded recipient.** The digest and the public
  issue are *published to GitHub*, so GitHub Inc (US) receives the third-party handles and
  comment snippets. `cron-daily-triage`'s public issue comments are the same. PA-31 `(d)`
  must name GitHub Inc as a recipient and `(e)` must record its DPF + SCCs Module 2 transfer
  — the Vendor Mapping row already carries that mechanism, but PA-31 must claim it.
- **`GDPR-Art-5e` / `GDPR-Art-17` — Sentry is a recipient of content here, unlike PA-27.**
  PA-27 could state "Sentry/Better Stack are NOT recipients of content" because its keys are
  scrubbed by `SENSITIVE_KEY_NAMES`. That claim is **false for PA-31**:
  `formatTailForSentry` ships a ≤4000-char stdout/stderr tail through
  `redactGithubSourcedText`, which strips emails, phones, UUIDs, IPs, JWTs and credential
  shapes but **not usernames, handles, display names or free text** — and the fleet's stdout
  is collector JSON containing exactly those. PA-31 `(d)` must name Sentry as a recipient of
  a bounded tail that may contain third-party identifiers, and `(f)` must state its retention.
  Copying PA-27's Sentry sentence would be an over-claim.
- **`GDPR-Art-5e` — the self-hosted Inngest event/run store is a third PII surface.** PA-27
  already records it as operator-managed with **no automatic deletion**. The fleet's step
  payloads and run logs land in the same store. PA-31 `(f)` must record it rather than
  implying Anthropic's 30 days is the whole retention story.
- **`GDPR-Art-9` — the Art. 9 cell must reason like PA-27's, not deny.** Free-text Discord
  messages and HN comments structurally *may* carry special-category content unsolicited.
  The cell must follow PA-27's "may arrive unsolicited" treatment — controls plus a named
  residual — not assert "none by design". Separately, do **not** import the external
  research pass's error that Discord membership or GitHub contributor identity are themselves
  special categories; they are not.
- **`GDPR-Art-6` — the operator is a data subject too.** PA-27 `(b)` lists the operator as
  subject (iii) and PA-22 uses Art. 6(1)(b) for the operator alongside 6(1)(f) for the
  third-party limb. PA-31/PA-32 must state the basis for the **operator** population, not
  only the third-party ones.
- **Art. 14 must be assessed per arm, not monolithically.** D5's undischarged posture is
  right for the community population. Arm C (CI contributors) is different — contributors
  open PRs knowingly against a repo with published contribution terms — and Arm A is
  different again. The LIA must reach a per-arm conclusion.

### D6 — The two load-bearing distinctions are stated explicitly

Both must appear in the records in terms a reader cannot miss:

- **Output ≠ input minimization**, in PA-31 `(c)` and in the LIA Arm B, with the verbatim
  directives, their true scope (the "never list individual followers, commenters, or likers"
  directive is scoped **only to the LinkedIn section** of the digest), and the
  **counter-directives** that *mandate* stargazer usernames and a
  `| User | Issue/PR | Comment |` table in the published digest.
- **Art. 28 ≠ Art. 6**, in PA-31 `Lawful basis` and in the Vendor Mapping Notes: the
  Anthropic row is a vendor record; the lawful basis lives here. Art. 28 coverage is
  unaffected — the DPA auto-incorporates via Commercial Terms §C at the account level.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md` | Art. 6(1)(f) LIA — arms A, **B1 (collection/egress)**, **B2 (republication)**, C + the Art. 14 section + the PA-17 trigger discharge. B1/B2 are split because they reach **opposite** conclusions (D9). |
| `knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md` | Art. 35 screening memo covering PA-31 / PA-32 / PA-33 |
| `knowledge-base/project/specs/feat-one-shot-7100-art30-eval-fleet-register/decision-challenges.md` | ✅ **already written** — UC-1…UC-4 per ADR-084; `/ship` renders it into the PR body and files an `action-required` issue |

## Files to Edit

| Path | Change |
|---|---|
| `knowledge-base/legal/article-30-register.md` | Insert **PA-31, PA-32, PA-33** between PA-30's closing `---` and `## Register Maintenance`; **amend PA-17** (below); extend the **Anthropic PBC** Vendor Mapping row (Activities + Notes); bump `last_reviewed`; add a counsel-review item if D4 lands on arm (ii) |
| ↳ **PA-17 amendment** (same file) | Required, not optional — the #4558 "first third-party-personal-data repository" trigger **fired ~5 months ago and was not honoured**, so a new LIA alone does not discharge it. Three edits: (a) a dated note recording that the trigger fired, when, and that the re-opened balancing lives in PA-32; (b) correct the §(c) carve-out asserting third-party content is *"display-only"* — it now egresses to Anthropic and reappears in public issue comments; (c) narrow the §(g) TOM claiming render-time redaction is *"the load-bearing Art. 14 gate"*, since `redactGithubSourcedText` demonstrably redacts neither handles nor free text. |
| `knowledge-base/legal/data-processing-agreements/anthropic.md` | `register_activity_refs: [PA-22, PA-27, PA-31, PA-32, PA-33]` (drop the INCOMPLETE marker); correct `role:`; correct the enumeration in the 2026-07-30 bullet; add a dated resolution note |
| `knowledge-base/legal/compliance-posture.md` | New changelog comment at the top of the reverse-chron block; rewrite the `#7100` parenthetical in the Anthropic PBC row; add the Art. 14 + drift-guard residuals as **Active Compliance Items** rows; bump the Art. 30 register row's Last Updated in `## Legal Documents`; bump `last_updated` frontmatter |

**Open Code-Review Overlap: None.** Queried all 62 open `code-review`-labelled issues for
each path above (`gh issue list --label code-review --state open --json number,title,body`,
then `jq --arg path … contains($path)`); zero matches.

**Out of scope (hard):** no source file, no workflow YAML, no `docs/legal/**`, no
`plugins/soleur/docs/**`. The records describe the system as it is.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing a word)

0.1 Re-derive the fleet enumeration from the worktree rather than from this plan, and pin
the results into the LIA's provenance section:

**Canonical enumeration probe** — measured 2026-07-31 on this worktree; these are the
expected values, not guesses. Use absolute paths (the Bash tool resets cwd between calls):

```bash
D=apps/web-platform/server/inngest/functions

# The 15 CLI-egress crons = spawnClaudeEval callers UNION direct resolveClaudeBin callers.
# This union is the honest scope; neither half alone is.
{ grep -lE 'spawnClaudeEval\(\{' "$D"/cron-*.ts
  grep -lE 'resolveClaudeBin\(\)'  "$D"/cron-*.ts; } | sort -u | wc -l     # → 15
grep -lE 'spawnClaudeEval\(\{' "$D"/cron-*.ts | wc -l                       # → 13
grep -lE 'resolveClaudeBin\(\)'  "$D"/cron-*.ts | wc -l                     # →  2
grep -rlE 'from "\./_cron-claude-eval-substrate"' "$D" | wc -l              # → 20
grep -rn  'postAnthropicMessage({' "$D"                                     # →  3 callers

# The full 21-member PA-31 set (15 CLI crons + 3 HTTP crons + event-ship-merge + 2 oneshots).
# Two INDEPENDENT predicates must agree byte-for-byte; their agreement is the load-bearing
# property, and it is what makes the D2 scope mechanically checkable.
grep -lE 'ANTHROPIC_API_KEY' "$D"/{cron,oneshot,event}-*.ts | sort > /tmp/setA
grep -lE 'spawnClaudeEval\s*\(|resolveClaudeBin\s*\(|postAnthropicMessage\s*\(' \
      "$D"/{cron,oneshot,event}-*.ts | sort > /tmp/setB
diff /tmp/setA /tmp/setB && wc -l < /tmp/setA                                # → identical; 21
```

**Disposition on mismatch (mandatory).** If any measured value here disagrees with the
figures recorded in this plan, the **measurement wins**: authoring stops, the member snapshot
is rebuilt from the measurement, and the divergence is noted in the LIA's provenance section.
It is never reconciled by editing the expected value in this plan. The entire reason #7100
exists is that an enumeration was wrong and downstream records restated it.

Both direct-spawn crons set `ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY`
(`cron-daily-triage.ts:197`, `cron-follow-through-monitor.ts:310`), which is what makes
them egress members despite bypassing the helper. Both carry the ADR-033 **I2** header
comment ("Operator `ANTHROPIC_API_KEY` only; never founder BYOK"), the invariant that fixes
Jikigai as controller and Anthropic as processor for the whole fleet.

The union predicate above is also the natural detection rule for the deferred drift guard
(`## Deferred Work` item 2) — CTO input governs its final shape.

0.2 Confirm the next free PA number **against `origin/main`**, not against the worktree —
a sibling PR in this session's batch can claim 31/32 concurrently (the ADR-ordinal
collision class; the PA-16 collision in PR #4213 is the in-register precedent):

```bash
git fetch origin main
git show origin/main:knowledge-base/legal/article-30-register.md \
  | grep -nE '^## Processing Activity [0-9]+ — ' | tail -3
```

0.3 Confirm workflow states are still current (`gh workflow list --all | grep -iE 'fix-constraints|claude|pretooluse'`).

0.4 Read in full, for house style: PA-17, PA-22, PA-27, PA-30; the PA-27 LIA and DPIA memo;
`2026-07-07-beta-crm-lia.md` (Art. 14 section); the counsel review.

### Phase 1 — Author the LIA

Three arms per D3; the Art. 14 section per D5; the PA-17 trigger discharge stated
explicitly. Frontmatter follows the LIA class:
`title` / `type: legitimate-interest-assessment` / `date` / `plan` / `issue` /
`status: draft-requires-counsel-review` / `controller` / `processing_activity` /
`lawful_basis` / `data_subjects` / `related[]`. Opens with the DRAFT blockquote.

**External-authority rule (load-bearing).** Every external authority cited — EDPB
guideline number, CJEU case number, CNIL page, Commission decision — must be
**WebFetch-verified at authoring time**, with the verification date recorded inline. Any
citation that cannot be verified against a primary source is **dropped**, not hedged. A
legal record citing a guideline number that does not exist is worse than one citing
nothing. Specifically:

- EDPB **Guidelines 03/2026** on web scraping in the context of generative AI — cite as
  **adopted 8 July 2026 for public consultation, open until 30 October 2026**, i.e. a
  **draft**. Note its scope is scraping in the *generative-AI* context; our purpose is
  operational LLM use, so the collection limb is analogous and the training limb is not.
  State that distinction rather than over-applying it.
- **EU-US DPF**: adequacy decision in force; General Court dismissed *Latombe v Commission*
  (T-553/23) on 3 September 2025; appeal pending before the CJEU as **C-703/25 P**. The
  existing register wording "DPF + SCCs M2+3 + UK IDTA + Swiss Addendum" remains accurate;
  record that the SCCs are the standing fallback if the DPF is invalidated, and add the
  CJEU ruling as a re-evaluation trigger.

### Phase 2 — Author the DPIA screening memo

Per D4, both arms specified. Frontmatter follows the DPIA class
(`type: dpia-screening-memo`, `status: draft-requires-counsel-review`,
`processing_activity`, `conclusion`, `related[]`). Same external-authority rule.

### Phase 3 — Author PA-31, PA-32 and PA-33, and amend PA-17

> **Cell-ownership map (settles the D1-vs-AC conflict spec-flow flagged as P0-2).** The
> public-output limbs belong to **PA-32**, not PA-31. Where an AC below names PA-31 for a
> public-surface cell, PA-32 governs:
>
> | Cell | PA-31 (internal egress) | PA-32 (republication) |
> |---|---|---|
> | `(d)` recipients | Anthropic PBC; Sentry (bounded tail) | **+ the general public; GitHub Inc as host** |
> | `(e)` transfers | Anthropic US — DPF + SCCs M2+3 | **publication is NOT a Chapter V transfer (*Lindqvist*)** |
> | `(f)` retention | Anthropic 30-day; Inngest store no-auto-delete | **permanent; no erasure routine; 2 forks** |
> | input-vs-output distinction + counter-directives | — | **PA-32 `(c)`** |
> | member snapshot | the 21-member egress set | its own 2-member limb list (`cron-community-monitor`, `cron-daily-triage`) |
>
> **Snapshot partition (P0-3).** The Phase 0.1 probe yields one 21-member egress set. PA-31's
> snapshot is that full set — membership in PA-31 is by *egress*, which both
> `cron-community-monitor` and `cron-daily-triage` satisfy. PA-32 does **not** carry a
> competing snapshot; it records the two members whose **public-output limb** it governs, and
> cross-references PA-31 for their egress limb. A member therefore appears in PA-31 for one
> operation and PA-32 for another — which is correct under Art. 4(2) and is why the deferred
> drift guard asserts against **PA-31's** snapshot only.

Current-generation 10-row schema, in this exact order:
`**(a) Purpose**` · `**(b) Categories of data subjects**` · `**(c) Categories of personal data**` ·
`**Special categories (Art. 9 / 10)**` · `**Lawful basis**` · `**(d) Recipients**` ·
`**(e) Third-country transfers + safeguards**` · `**(f) Retention**` · `**(g) TOMs (Art. 32)**` ·
`**(h) DSAR (Art. 15 / 20)**`.

House-style constraints, all verified against the register:

- Envelope: `---`, then `## Processing Activity NN — <Title> (#7100)`, then a parenthetical
  preamble ending `**Brand-survival threshold: single-user incident.**`, then the table,
  then `---`.
- Table opens `| Art. 30(1) limb | Entry |` / `|---|---|`.
- **DPIA status, vendor-DPA pointers and DSAR statements live inside the `(g)` tail as
  inline bolded sub-labels** — there are no `**LIA**`, `**Art. 14**`, `**DPIA screening**`
  or `**Re-evaluation trigger**` rows anywhere in the register.
- Insert **after PA-30's closing `---` and before `## Register Maintenance`**.

PA-31 must carry: the egress-scope predicate + dated member snapshot (D2); the tiered `(b)`
cell distinguishing the repo, community and operator populations with the Art. 14 status
(D5); the input-vs-output distinction with verbatim directives *and* counter-directives
(D6); `(e)` recording the operator-keyed Anthropic transfer; `(f)` recording **both** the
Anthropic 30-day default under the unsigned Zero-Retention amendment **and** the permanent,
erasure-routine-less public digest in git history; `(g)` recording the containment measures
honestly — including, per the substrate's own comment, that the collectors' child
`curl`/`gh api` calls are **grandchild processes not gated by the PreToolUse hook** — plus
the named residual for the missing drift guard.

**PA-33** (CI surface — this paragraph was mis-labelled PA-32 before the D1 reversal) must
carry: the `pull_request` trigger and path filter; `permissions: contents: read`; the
PR-head-SHA checkout with `persist-credentials: false`; the keyless-preflight fork-exclusion;
the action pin and model; and the honest note that the trigger is path-filtered while the
agent's `Read`/`Grep` reach the **whole** checked-out tree.

PA-32 (community observation + republication) must additionally carry, per CLO Q5 — these are
the limbs the first draft omitted:

- **`(d)`** — "**the general public**" as a recipient category, and **GitHub Inc as
  recipient/host** of the public surface. This *inverts* PA-17's "GitHub is the source, not a
  recipient" framing; say so, or the two entries silently contradict.
- **`(e)`** — state explicitly that publication to a world-readable site is **not** a Chapter V
  transfer (*Bodil Lindqvist*, C-101/01), so no reader concludes the SCCs cover it. The
  Anthropic egress is the Chapter V limb. Distinguish them or the cell misleads.
- **`(f)`** — "indefinite / permanent; no erasure routine; 2 forks" is itself an Art. 5(1)(e)
  storage-limitation **finding**. Record it as a finding, not a blank.
- **Art. 22 negative determination** — PA-27, PA-28 and PA-30 all carry one and PA-22 carries a
  dedicated brief. Both new entries need one, especially `cron-daily-triage`, which auto-labels
  and comments on third parties' issues.
- **Art. 5(1)(b) / Art. 6(4) purpose compatibility** — Discord data is obtained for community
  operation; republishing it as positioning content is a further purpose needing a
  compatibility assessment.
- **Art. 15/20, Art. 21(1)** — cross-reference deferred items 8 and 9.
- **Discord Developer Policy** — a contractual limb on retention/republication of member data
  obtained via the API. Non-GDPR, but PA-15 is the register's precedent for recording
  platform-terms constraints.
- **Non-EU** — one line that CCPA/CPRA and Québec Law 25 thresholds are not met. Say it rather
  than leaving it silent.

PA-33 must additionally address **CLA coverage**: whether the individual/corporate CLA grant
covers transmitting contributor-authored source to a third-party AI processor. Cross-reference
PA-7.

**Two source discrepancies to cite precisely, not merge:** the snippet cap is `.[:120]` in
`github-community.sh` (`body_snippet`) while the prompt authorises quotes "under 100 chars" —
different mechanisms, cite both. And #7075 links a digest file that does not exist, so the
file-write limb's live state must be **re-verified at merge** rather than asserted.

Then extend the **Anthropic PBC** Vendor Mapping row's Activities and Notes columns (preserving
the `Anthropic.*PA-22.*autonomous` token order per AC11i), and bump `last_reviewed`.

### Phase 4 — Reconcile the two downstream records

`anthropic.md` and `compliance-posture.md` per `## Files to Edit`. Correct the stale
enumeration in the 2026-07-30 bullet rather than leaving it to contradict the new PA.

### Phase 5 — File the deferred issues, then verify

Create the follow-up issues in `## Deferred Work` **in this PR's lifecycle** and wire their
numbers into the PA `(g)` tails, the LIA, and the `compliance-posture.md` Active Items rows.
A deferral without a tracking issue is invisible (`wg-when-deferring-a-capability-create-a`).
Then run the Acceptance Criteria.

## Acceptance Criteria

### Pre-merge (PR)

Anchor on content, never on line numbers (`cq-cite-content-anchor-not-line-number`). Use
flag-based `awk`, never `/start/,/end/` ranges — the range self-matches its start line and
silently returns a heading-only body.

- **AC1 — three entries exist, exactly once each.** `grep -cE '^## Processing Activity 31 — '` returns `1`; same for `32` and `33`. Anchored on the heading form, because bare `PA-31` also matches legitimate cross-references.
- **AC2 — no number collision.** After the final rebase, `git show origin/main:knowledge-base/legal/article-30-register.md | grep -cE '^## Processing Activity (31|32|33) — '` returns `0`.
- **AC2a — PA-32 records the lawful-basis failure (D9).** PA-32's `Lawful basis` cell states that Art. 6(1)(f) is **not available** for the republication limb as implemented, names the **necessity** limb as the point of failure, cites the R1–R5 remediation issue, and cites `2026-07-07-beta-crm-lia.md` as the internal precedent that already rejected git-committed PII as an Art. 17 impossibility. The cell contains **no** unqualified assertion that legitimate interest prevails for that limb.
- **AC2b — PA-17 is amended (CLO Q4).** PA-17 carries a dated note recording that the #4558 trigger **fired** (with the ~2026-03-19 date and a pointer to PA-32); its `(c)` "display-only" carve-out is corrected; and its `(g)` render-time-redaction claim is narrowed. `grep -c '4558' knowledge-base/legal/article-30-register.md` increases relative to `origin/main`.
- **AC2c — the materialised state is recorded, not projected.** PA-32 `(f)` states the digest count and date range, that the repository is public with 2 forks, and that no deletion has ever occurred — each traceable to a command in the LIA's provenance section, and **re-verified at merge** (the file-write limb's live state is disputed; #7075 links a nonexistent digest).
- **AC3 — schema conformance.** For each new entry, the flag-based extraction
  `awk '/^## Processing Activity 31 — /{f=1;next} /^## /{f=0} f' … | grep -cE '^\| \*\*'`
  returns `10`, and the ten row labels appear in the canonical order. The `(h) DSAR` row is
  **required** for both entries: there is no DB table behind them, so the row must state the
  honest Art. 15 route for a community member or contributor rather than being omitted.

  **Verifier pre-tested 2026-07-31** against known-good, known-broken and empty controls, as
  the Sharp Edge on `awk` ACs requires — the expected values below are measured, not assumed:

  | Probe | Result |
  |---|---|
  | `grep -cE '^## Processing Activity 27 — '` (AC1 form, existing entry) | `1` ✅ |
  | Flag-based row count on PA-27 (9 rows — no `(h)`) | `9` ✅ |
  | Flag-based row count on PA-30 (10 rows — has `(h)`) | `10` ✅ |
  | Flag-based row count on a nonexistent `Processing Activity 99` | `0` ✅ (broken control fails) |
  | **Naive `awk '/^## Processing Activity 27 — /,/^## /'`** | **`0`** ❌ — the range self-matches its start line and yields a heading-only body. This is the trap; the flag-based form above is mandatory. |
  | AC13 resolver against the existing PA-27 DPIA memo | no output ✅ (clean file ⇒ non-empty output is a real signal) |
- **AC4 — placement.** The new entries sit after the PA-30 block and before `## Register Maintenance`; verified by comparing `grep -n` ordinals for the four anchors.
- **AC5 — lawful basis is a controller-side determination.** PA-31's `Lawful basis` cell contains `Art. 6(1)(f)` and a path to the new LIA file, and the LIA path resolves on disk.
- **AC6 — input ≠ output is stated.** PA-31 `(c)` and the LIA both assert that the minimization directives bind the digest output and not the model input, and both name at least one counter-directive (stargazer usernames or the commenter table). Asserted by grepping a distinctive phrase authored for the purpose — not by an absence-grep, which would false-fail on the very sentences that state the distinction.
- **AC7 — Art. 28 ≠ Art. 6 is stated** in PA-31 and in the Vendor Mapping Notes.
- **AC8 — PA-17 trigger addressed.** The LIA names the "first third-party-personal-data repository" trigger, cites `knowledge-base/legal/audits/2026-05-counsel-review-4558.md`, and states how it is honoured.
- **AC9 — Art. 14 status is unambiguous.** PA-31 `(b)` and the LIA state the obligation, that it is undischarged, and the tracked issue number. No occurrence of an asserted Art. 14(5)(b) *discharge* for the community population.
- **AC10 — DPIA memo exists and both PAs cite it** from their `(g)` tails, with a `DPIA status:` sub-label. The memo's `conclusion` frontmatter is non-empty and matches its body.
- **AC11 — retention is honest.** PA-31 `(f)` names the Anthropic 30-day default, the unsigned Zero-Retention amendment, the permanent public digest with no erasure routine, **and** the self-hosted Inngest event/run store's no-automatic-deletion posture.
- **AC11a — all recipients are named (D7).** PA-31 `(d)` names **Anthropic PBC**, **GitHub Inc** (host of the published digest and issues) and **Sentry** (bounded stdout/stderr tail), and `(e)` records GitHub's DPF + SCCs Module 2 transfer. The entry contains **no** claim that Sentry is not a recipient of content.
- **AC11b — Art. 9 is reasoned, not denied (D7).** The `Special categories (Art. 9 / 10)` cell follows PA-27's "may arrive unsolicited" treatment with a named residual; it does not read "None by design", and it does not describe Discord membership or contributor identity as special categories.
- **AC11c — the operator population has a stated basis (D7).** PA-31 and PA-32 `(b)` name the operator as a data subject and `Lawful basis` states the basis for that population distinctly from the third-party limb.
- **AC11d — the allowlist TOM is scoped, not universal (D8).** PA-31 `(g)` names
  `cron-daily-triage` and `cron-follow-through-monitor` as members that run **without** a
  `PreToolUse` hook, allowlist or `runHookSelfTest`, and states the Tier-2 egress firewall as
  their sole compensating control. The entry contains **no** unqualified claim that every
  member runs under a deny-by-default command allowlist, and makes **no** assertion either way
  about the CLI's own sandbox for those two (not determinable from source).
- **AC11e — no inherited PII-scrub claim (D8).** ~~PA-31 `(g)` contains **no** reference to
  `sanitizePromptString` or to prompt-assembly email scrubbing~~, and states affirmatively that
  no PII scrub is applied to Anthropic-bound content on this path.

  **AMENDED 2026-07-31 at verification time — the original absence-grep was defective.** Run
  literally, `grep -c 'sanitizePromptString'` over PA-31 `(g)` returns `1` and the AC FAILS —
  but the artifact is correct and the criterion is wrong. The single occurrence reads:
  *"**NO PII SCRUB EXISTS on Anthropic-bound content on this path.** PA-22 records
  `sanitizePromptString` plus email scrubbing at prompt assembly as its Art. 32 measure;
  **that measure does not exist here**, and on the CLI path it structurally could not…"* —
  i.e. it names the measure precisely in order to **disclaim** it, which is strictly more
  informative to a supervisory authority than omitting the name.

  This is the failure mode **AC6 already warns about** in this same plan ("not by an
  absence-grep, which would false-fail on the very sentences that state the distinction"), and
  AC11e reproduced it. Replaced with positive assertions:

  1. `awk`-extracted PA-31 `(g)` contains `NO PII SCRUB EXISTS` → **PASS**
  2. it contains `that measure does not exist here` → **PASS**
  3. every occurrence of `sanitizePromptString` in PA-31 is within a disclaiming sentence —
     verified by reading, not by counting.

  Recorded as an amendment rather than silently satisfying a looser command, per the
  "verify an AC by running its LITERAL command" rule.
- **AC11f — exclusions are named (D8).** PA-31 names `agent-on-spawn-requested` (→ PA-22),
  `cron-anthropic-cost-report` (`ANTHROPIC_ADMIN_KEY`), `cron-skill-freshness`, and the CI
  workflows (→ PA-33) as deliberate exclusions, each with its reason.
- **AC11g — PA-33 keys on the secret, not the action (D8).** PA-33's member set equals
  `grep -rl 'secrets.ANTHROPIC_API_KEY' .github/` as of the snapshot date. **Measured
  2026-07-31 — five files, not one:**

  | Member | Trigger | Note |
  |---|---|---|
  | `.github/workflows/fix-constraints-stage-a.yml` | `pull_request`, `workflow_dispatch` | `claude-code-action`; **active**; PR-head-SHA checkout |
  | `.github/workflows/ci.yml` → `sandbox-canary-capture-gate` (job at `^  sandbox-canary-capture-gate:`) | `push:[main]`, `pull_request`, `merge_group` | step-level `env:`, **not** `claude-code-action` |
  | `.github/workflows/ci.yml` → `plugin-root-propagation-gate` (job at `^  plugin-root-propagation-gate:`) | same | step-level `env:`; in-source comment "Creds-gated (one paid Haiku turn)" |
  | `.github/workflows/test-pretooluse-hooks.yml` | `workflow_dispatch` only | `claude-code-action`; hardcoded synthetic prompt ⇒ nil personal data |
  | `.github/actions/anthropic-preflight/action.yml` | composite | shared credential-liveness probe; name once, not per caller |

  Note `ci.yml` also fires on `push:[main]` and `merge_group`, so those two jobs make paid
  Anthropic calls outside the PR context too — the record must not describe PA-33 as
  PR-only. Each member carries its trigger class and workflow state, with
  `claude-code-review.yml` recorded as `disabled_manually` **and** flagged as GitHub API
  state invisible to source inspection, with the verification date and method
  (`gh workflow list --all`).
- **AC11h — qualified measures are qualified (D8).** `(g)` describes teardown as fail-open
  with a Sentry mirror and a GC backstop; gives the env-var range (most members 4–6,
  `cron-community-monitor` 18); and frames the grandchild-process gap as two measures at two
  layers — the allowlist constrains the instructions the model may issue, while egress from an
  allowlisted script's process tree is constrained **only** at the network layer by a
  destination-only, content-blind firewall.
- **AC11i — `check-pa-22.sh` still passes (D8).** After the Vendor-row edit,
  `bash scripts/check-pa-22.sh` exits 0 — the row must retain a single line matching
  `Anthropic.*PA-22.*autonomous` in that token order.
- **AC12 — downstream records reconciled.** `anthropic.md` frontmatter carries `PA-31`, `PA-32` and `PA-33` and contains **no** `INCOMPLETE` token; `compliance-posture.md` contains no remaining `tracked as #7100` phrasing in the Anthropic row, and its `last_updated` equals the PR date.
- **AC13 — every internal citation resolves.** Run the resolver over the five artifacts and
  assert no output:

  ```bash
  grep -ohE '(knowledge-base|docs|apps|plugins|scripts|\.github)/[A-Za-z0-9/_.-]+\.(md|ts|sh|yml|mjs|txt|tsx)' \
    <the five artifacts> | sort -u | while read -r p; do [[ -e "$p" ]] || echo "BROKEN: $p"; done
  ```

  **Self-reference carve-out (mandatory).** Exclude paths this PR itself creates or defers —
  the AC-self-grep hazard. When run against **this plan** on 2026-07-31 the resolver returned
  exactly three lines, all of them forward references, which is the expected shape:
  the LIA and the DPIA memo (created by Phases 1–2) and
  `apps/web-platform/test/server/anthropic-egress-register-sweep.test.ts` (deferred item 2,
  intentionally absent). At AC time the LIA and memo will exist, so the only permitted
  remaining line is the deferred sweep path. **Any other `BROKEN:` line is a real failure.**
  Do not widen the carve-out to silence a genuine break — rephrase the citation instead.
- **AC14 — every external authority is verified.** Each external citation in the LIA and the DPIA memo carries an inline verification date, and EDPB Guidelines 03/2026 is described as a consultation draft with its 30 October 2026 closing date. No citation lacks a verifiable primary source.
- **AC15 — enumeration matches code.** The member snapshot in PA-31 equals the output of the Phase 0.1 greps, re-run at AC time. Every claim the diff **adds** about the code traces to a named file anchor — an absence-only AC set can pass in full while the added claims are false.
- **AC16 — deferred issues exist and are wired.** Each **unconditional** item in
  `## Deferred Work` is created, and its number appears in the PA `(g)` tail, the LIA, and a
  `compliance-posture.md` Active Items row. **Conditional items are excluded from this count**
  — item 5 (full DPIA) is filed **only if** D4 lands on arm (ii). Without this carve-out AC16
  would force filing a full-DPIA issue for a DPIA the assessment just concluded is not
  required, or fail. (Logic bug caught at plan review.)
- **AC17 — scope held.** `git diff --name-only origin/main...HEAD` lists only paths under
  `knowledge-base/legal/` and `knowledge-base/project/{plans,specs}/`. Both directories are
  accounted for in `## Files to Create` / `## Files to Edit` — including
  `knowledge-base/project/specs/feat-one-shot-7100-art30-eval-fleet-register/decision-challenges.md`,
  so the scope AC and the file manifest agree.

*(Cut at plan review: a full-suite AC. `AC17` proves the diff is markdown-only under
`knowledge-base/`, which cannot change a vitest outcome; the realistic failure mode was a
pre-existing unrelated red forcing `wg-when-tests-fail-and-are-confirmed-pre` triage on a docs
PR. CI runs the suite on the PR regardless.)*

### Post-merge (operator)

None. Every step is automatable in-session and is executed by `/work` or `/ship`.

## Observability

Not applicable — pure-docs change. No file under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/` or `plugins/*/scripts/` is touched, and no infrastructure surface is
introduced, so the Phase 2.9 gate skips by its own stated criteria. The compliance-item
rows added to `compliance-posture.md` are the operator-visible tracking surface for the
residuals this record names.

## Architecture Decision (ADR/C4)

None. This plan makes no architectural decision — it records an existing system. No ADR is
created or amended, and no `.c4` change arises: the record adds no external actor, external
system, container, data store or access relationship. The actors and systems involved
(Anthropic PBC as an external system; GitHub; the Inngest cron plane) are pre-existing and
unchanged by a documentation edit. The `check-pa-22.sh`-style register sentinel and the
fleet drift guard are deferred engineering work, not decisions taken here.

## Gates Assessed and Skipped

| Gate | Disposition |
|---|---|
| 1.4 Network-outage checklist | **Spurious trigger.** The substring `timeout` appears in the feature description only as code constants (`MAX_TURN_DURATION_MS`, `timeout-minutes`). This is a legal-records change, not a connectivity diagnosis; there is no `## Hypotheses` section for the checklist to populate. `hr-ssh-diagnosis-verify-firewall` is not engaged. |
| 1.5 Community discovery | No uncovered stack — the change is markdown under an existing convention. |
| 1.5b Functional overlap | Checked in-repo: `soleur:legal-generate` / `legal-document-generator` produce drafts and `legal-compliance-auditor` audits, but the house pattern for PA entries, LIAs and DPIA memos is **hand-authoring against precedent** (PA-27). No registry search warranted. |
| 2.8 Infrastructure-as-Code | No new infrastructure. |
| 2.9 Observability | Skipped per its own criteria (pure-docs). Recorded above. |
| 2.10 ADR / C4 | Skipped with rationale recorded above. |
| 2.11 Encryption posture | No persistent store and no new cross-component connection introduced. The **existing** transfer's safeguards are recorded in PA-31 `(e)`, which is the correct home for them. |
| CI gates on the touched paths | `legal-doc-cross-document-gate.yml` fires only on DSAR code surfaces; `tc-document-sha-guard` covers `docs/legal/*.md` only; `scripts/lint-infra-no-human-steps.py` scans only `knowledge-base/legal/runbooks`. **No CI gate fires on the paths this PR touches** — which is precisely why the ACs must be self-standing. |

## Domain Review

**Domains relevant:** Legal, Engineering. (Product: **NONE** — no user-facing surface; the
mechanical UI-surface override did not fire, as no path in `## Files to Create` or
`## Files to Edit` matches `components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx`.
Finance, Marketing, Sales, Support, Operations: not engaged by a legal-record edit.)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Reproduced all three corrected counts independently, then found five further
defects in this plan's own framing — folded as **D8**, with the two most consequential
independently re-verified by the planner. Headline findings: two of the fifteen CLI crons run
with no containment hook at all (so the Art. 32 TOM cannot be stated uniformly); no PII scrub
exists on the Anthropic-bound content (so PA-22's TOM must not be inherited); PA-33's
`claude-code-action` framing is false on the day it would be written (five `.github/` files
carry the secret, only three use the action); a fourth Anthropic-egressing cron
(`cron-anthropic-cost-report`, `ANTHROPIC_ADMIN_KEY`) needs naming as a deliberate exclusion;
and the two independent membership predicates agree byte-for-byte at 21 files, which is what
makes the D2 predicate mechanically checkable. Also raised **UC-1** (see
`## Decision Challenges`): the docs-only scope leaves the record's integrity resting on author
diligence, with `scripts/check-pa-22.sh` as standing evidence that deferral produces dead
sentinels.

### Legal (CLO)

**Status:** reviewed
**Assessment:** The most consequential review of the session. It **reversed D1** (two entries
→ three, organised by the public-output operation), **reversed the D9 lawful-basis question**
(Art. 6(1)(f) is *not* available for the republication limb — it fails at necessity before
balancing, and PA-30's own LIA already rejected "git-committed PII, an Art. 17 impossibility"
for a different activity), **reframed D5** (Art. 14 is not "open" but overdue since
~2026-03-19, and 14(5)(b) fails for the Discord and GitHub-commenter populations), and
established that **PA-17 must itself be amended** — its trigger fired ~5 months ago and a new
LIA alone does not honour it.

It also established that the republication is **materialised, not prospective**: 80 digests
since 2026-02-19 on a public repo with 2 forks, 46 carrying the commenter table, 65 naming
stargazers, named Discord members with handles and affiliations, one verbatim private-guild
quote disclosing an employer context, and zero deletions ever. And it found **two published
legal documents that are now false** (UC-3) — the #7086 Finding 4 failure class, in the
outward-facing docs.

Verdicts: D1 **revise → three**; D2 **correct and independently vindicated**, but downgrade
the drift-guard residual to a named follow-up test; D3 **correct in form, split arm B into
B1/B2** (they reach opposite conclusions); D4 **correct not to prejudge — and likely to
conclude a full DPIA IS required** for PA-32 (5+ WP248 criteria vs PA-27's 2), noting Art.
35(1) requires it *prior to* processing, so it is overdue; D5 **defensible, reframe required**;
D6 **both correct, both need strengthening**. Missing limbs folded into Phase 3.

CLO flagged that at PR time the `/ship` Phase 5.5 Counsel-Review CLO-Attestation gate fires on
`knowledge-base/legal/**` and will require per-artifact attestation.

### Product/UX Gate

Not applicable — Product assessed NONE and the mechanical override did not fire.

## Deferred Work

Each is filed as a GitHub issue during this PR's lifecycle, with re-evaluation criteria and
a milestone from `knowledge-base/product/roadmap.md`.

0. **🔴 R1–R5 — minimise or cease the republication limb (D9).** The blocking item. R1–R3 are
   prompt-string edits to `cron-community-monitor.ts`; R4 is a small handler-side redaction
   pass over the digest file and issue body before persistence; R5 is a retention/erasure
   posture for published artifacts, or an explicit finding that none is possible. CLO
   estimate: about a day. **Until R1–R4 land, PA-32 records that this limb has no available
   lawful basis.** Re-evaluate: immediately.
1. **Art. 14 notice — multi-channel, not one section (D5).** (a) A pinned notice or
   server-description line in the Discord guild Jikigai operates; (b) a line in the repo's
   README / CONTRIBUTING / issue templates for GitHub commenters; (c) Privacy Policy §4.15
   following the §4.13/§4.14 pattern, mirrored to
   `plugins/soleur/docs/pages/legal/privacy-policy.md`, with the pinned SHA refreshed in
   `apps/web-platform/lib/legal/legal-doc-shas.ts`. Art. 14(5)(b) fails for (a) and (b), so
   §4.15 alone does **not** discharge the obligation. **Re-evaluate: immediately — the
   obligation has been overdue since ~2026-03-19 and accrues daily.**
1a. **🔴 Correct the false public statements (UC-3).** `docs/legal/privacy-policy.md` §4.4
   ("is not controlled by Soleur") and `docs/legal/gdpr-policy.md` §2.2 (BYOK-only framing).
   Same failure class as counsel review #7086 Finding 4, which was rated BLOCKING. One
   sentence each plus the mirror and SHA refresh. **Strongly recommended for this PR — see
   UC-3.**
2. **Register-vs-code drift guard.** A vitest source sweep at
   `apps/web-platform/test/server/anthropic-egress-register-sweep.test.ts` asserting: the two
   independent membership predicates agree; the derived set equals PA-31's snapshot; the
   `.github/` `secrets.ANTHROPIC_API_KEY` grep equals PA-33's snapshot; and every CLI member
   is either in `CRON_BASH_ALLOWLISTS` or on an explicit exception list. Non-vacuity guard
   plus fixture proofs, mirroring `cron-no-byok-lease-sweep.test.ts`'s second `describe`.
   **Vitest, not `scripts/*.sh`** — the existing `test/**/*.test.ts` include picks it up with
   zero CI wiring, and the wiring step is the one that demonstrably failed last time.
   **Do NOT extend `cron-no-byok-lease-sweep.test.ts`**: it carries one *inverse* invariant
   (ADR-033 I2, "cron files MUST NOT call `runWithByokLease`"), so a register-membership
   failure would surface to a stranger as a BYOK security violation — trading a silent-false
   record for a mislabelled red build. **Re-evaluate: before the next new cron lands.**
   **See `## Decision Challenges` UC-1 — the CTO assesses this deferral as not defensible.**
3. **Input-side minimization for the community collectors.** The Discord collectors emit raw
   API objects with no `jq` projection; HN emits untruncated comment text. Projecting at the
   collector boundary would reduce what reaches Anthropic at all — a genuine Art. 25(1)
   data-protection-by-design measure rather than a prompt directive.
4. **Erasure path for published digests.** Today a community member has no route to have
   their handle or quoted comment removed from the digest or its git history. Needed for a
   defensible Art. 17 answer.
5. **Full DPIA** — **CONDITIONAL**, filed if and only if D4 lands on arm (ii). Excluded from
   AC16's "every deferred item is filed" count; see AC16's carve-out.
6. **Close the containment-hook gap on the two unhooked crons** (D8). Route
   `cron-daily-triage` and `cron-follow-through-monitor` through `setupEphemeralWorkspace`
   (or register an equivalent `PreToolUse` hook + allowlist for them) so the Art. 32 TOM can
   be stated uniformly instead of with a two-member carve-out. **Re-evaluate: this is a real
   containment gap, not merely a documentation asymmetry.**
7. **Art. 32 — prompt-injection-to-public-publication (CLO Q5).** The digest is written by an
   LLM over attacker-controllable input (anyone may post in the guild, comment on an issue, or
   post to HN) and the output **auto-merges to a public repo and auto-publishes as a public
   issue, with no human gate and no output allowlist**. PA-27 bounded its equivalent residual
   with "no tools + a closed `MAIL_CLASS_ALLOWLIST`"; here neither bound exists **and** a
   publication tool does. A genuine Art. 32(1)(b) finding. Overlaps R4.
8. **Art. 15/20 reachability for git-committed artifacts and issue bodies (CLO Q5).**
   `DSAR_TABLE_ALLOWLIST` covers DB tables only; there is no enumeration path for a digest or
   an issue body, so a DSAR from a Discord member is currently unanswerable by the existing
   machinery.
9. **Art. 21(1) objection route** for this population — required for any Art. 6(1)(f)
   processing; none of the nine legal documents mentions it.

*(Merged at plan review: the former item 7, "wire or delete `scripts/check-pa-22.sh`", is
folded into item 2 — same root cause (a register assertion nobody runs) and same fix, since
the proposed sweep can carry check-pa-22's single assertion for free. Phase 3 must still
preserve the `Anthropic.*PA-22.*autonomous` token order until it lands; AC11i enforces that.)*

## Decision Challenges

Recorded at `knowledge-base/project/specs/feat-one-shot-7100-art30-eval-fleet-register/decision-challenges.md`
per ADR-084. This session runs headless, so challenges to the operator's stated direction are
**persisted, not asked** — `/ship` renders them into the PR body and files an
`action-required` issue.

- **UC-1 — the docs-only scope is itself the failure mode this PR closes.** The register's
  integrity would rest on author diligence, and `scripts/check-pa-22.sh` is standing evidence
  that "tracked follow-up issue" produces dead sentinels. Asks for ~40 lines of vitest sweep
  in this PR. **Plan follows the operator's scope; this is the reason to revisit it.**
- **UC-3 — two published legal documents are now false, and the scope excludes the fix.**
  `docs/legal/privacy-policy.md` §4.4 tells the public that repository interaction data "is
  **not controlled by Soleur**" — affirmatively false, since Jikigai ingests it, sends it to
  Anthropic and republishes it. `docs/legal/gdpr-policy.md` §2.2 compounds it with BYOK-only
  framing. Same failure class as counsel review #7086 **Finding 4**, which was rated BLOCKING.
  Shipping a register that the published policy contradicts undercuts the PR's own purpose.
  **Highest-severity challenge in this session; strongly recommend accepting.**
- **UC-4 — the record will state that a live limb has no lawful basis.** Per D9, PA-32 will
  record that the republication limb fails Art. 6(1)(f) at the necessity limb, that Art. 17 is
  not implementable against git history and two forks, and that remediation R1–R5 is source
  work this PR cannot perform. The operator should see that this is what an honest record
  says; the alternative is the defect #7100 exists to fix.
- **UC-2 — the two unhooked crons.** Absorbed into D8 as an accuracy requirement; the
  remediation option is out of scope and filed as deferred item 6.

Items 3 and 4 are the code-side counterparts of the two findings this record documents; the
record's honesty depends on them being tracked rather than implied.

## Re-evaluation Triggers (to be recorded in the PAs and the LIA)

- The Art. 30 register next receives a new PA entry, **or** the first arms-length
  (non-Soleur) tenant — whichever is first (the trigger this issue mandates).
- Any fleet member pointed at a repository, Discord guild or social account other than
  `jikig-ai/soleur` and Jikigai's own properties.
- The Anthropic Zero-Retention amendment being signed, **or** remaining unsigned 90 days
  from this record's date while the fleet continues to egress third-party content.
- A fleet member gaining a new write path to a public surface carrying third-party personal
  data, beyond `cron-community-monitor`'s digest and `cron-daily-triage`'s issue comments.
- EDPB Guidelines 03/2026 being adopted in final form (consultation closes 30 October 2026).
- The CJEU ruling in **C-703/25 P** (*Latombe*), or any other change to the EU-US DPF's
  standing.
- Any EEA-out transfer not covered by the disclosed DPF/SCCs.

## Risks

| Risk | Mitigation |
|---|---|
| The record over-claims a compliance state (the defect class this PR exists to fix). | D5 records Art. 14 as undischarged; the DPIA conclusion is not prejudged (D4); the `(g)` cell records the grandchild-process hook gap honestly; AC14 forces external-citation verification. |
| PA number collision with a sibling PR in this batch. | AC2 re-verifies against `origin/main` after the final rebase, not just at authoring time. |
| The member snapshot decays. | D2's egress predicate + the named residual + deferred item 2. |
| A fabricated or over-stated external authority reaches a legal record. | AC14 + the Phase 1 external-authority rule. Already caught once in this session: the research pass reported EDPB Guidelines 03/2026 as "newly finalized" when it is a consultation draft open until 30 Oct 2026. |
| The plan's own code claims are stale by `/work` time. | Phase 0.1 re-derives them from the worktree rather than trusting this document. |

## Session Learnings to Capture

- One-blocked-mechanism reasoning recurs in enumerations: "15 crons call `spawnClaudeEval`"
  was verified accurate by counsel and is wrong, because two crons reach the same egress by
  a different helper. **Scope a compliance record by the boundary crossed, not by the
  function name that usually crosses it.**
- A research subagent reported a real EDPB guideline with a real URL but the wrong status
  ("finalized" vs. a consultation draft). Real-artifact-wrong-status is a distinct and more
  dangerous failure than fabrication, because the URL checks out.
