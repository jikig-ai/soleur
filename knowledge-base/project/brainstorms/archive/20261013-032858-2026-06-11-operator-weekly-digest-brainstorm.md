---
date: 2026-06-11
topic: operator-weekly-digest
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstormed
issue: 5085
---

# Brainstorm: Operator-Facing Weekly Comprehension Digest

## What We're Building

A weekly, plain-language **private** digest that tells the non-technical operator *"what your
company actually did this week"* — built to fight **business comprehension debt** (Addy Osmani,
*Loop Engineering*, June 2026): autonomous loops ship features, move money, and resolve
incidents faster than a solo owner can keep up with what their company is doing.

It is a **scheduled skill** run every Friday via `soleur:schedule` (GitHub Actions, repo checked
out). It reads the operator's own repo artifacts directly, asks Claude to synthesize them in a
calm chief-of-staff register, scrubs secrets/PII with the existing redaction sentinel, and posts
the result as a **private GitHub issue** in the operator's repo. A deterministic fallback renders
a usable (if unpolished) digest if the LLM call fails — the week is never silently blank.

**V1 sections (operator-selected):**
1. **What your company built** — merged PRs this week, rewritten in business terms (consequence,
   not commit messages / PR numbers / file paths).
2. **Money & vendors** — expense/vendor *changes* this week, derived by git-diffing
   `knowledge-base/operations/expenses.md` (the ledger is a snapshot, so "changes" = week-over-week diff).
3. **What broke & whether it's fixed** — one line per resolved post-mortem (post-redaction PIRs only).
4. **Action needed from you** — a weekly *recap* (summary + links) of open `action-required` issues.
   This section **links to** the operator inbox (#5103); it does **not** own or route decisions.

## Why This Approach

- **Distinct from the shipped community release digest (#5080).** That cron is *public/community*
  (Discord `#releases`), input set deliberately CLOSED to published GitHub Release bodies only,
  brand-promotional voice. #5085 is *private/operator*, input set deliberately OPEN to the internal
  business data the community digest excludes. The community digest's #1 safety rail ("no private
  content in a public post") **inverts** here into our crux: *operator business data must never reach
  the wrong/public channel.* Confirmed by learnings-researcher: no prior decision pre-decides this
  operator-vs-community split — it is a clean new surface, not a re-opening of #5080.

- **Scheduled skill, not an Inngest cron.** The operator's inputs (expense ledger, post-mortems,
  distribution-content) live in `knowledge-base/`, which is **NOT in the web-platform container
  image** (`cron-weekly-release-digest.ts:65-68`; learnings: "runtime KB reads in web-platform crons
  are dead code — hit the fallback 100%"). An Inngest cron would have to re-fetch every file over the
  GitHub Contents API and parse markdown tables in TS — brittle plumbing the learnings explicitly warn
  against. A GitHub Actions skill has the repo on disk for free, runs `redact-sentinel.sh` natively,
  and matches what the issue proposed ("via `soleur:schedule`").

- **Private GitHub issue channel (CLO + CTO converge).** First-party: no third-party processor ever
  sees the operator's financials/incidents (vs. email/Discord, which are third-party processors needing
  a DPA). GitHub API is already on every cron's egress allowlist — no new egress surface, no Tier-2
  concern. The operator reads it alongside other operator items.

- **Thin synthesizer, not five pipelines (CPO).** Reuse existing sources of truth rather than
  re-deriving: expense ledger, post-mortems, `gh pr/issue list`, distribution-content frontmatter.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Audience | Private, operator-only | Comprehension tool, not a marketing artifact; inverts #5080's public threat model |
| Sections (V1) | Built / Money / Incidents / Action-needed | Operator-selected; "content published" deferred (campaign-calendar already shows it) |
| Action-needed scope | Summarize + link only | Decisions owned by operator inbox #5103; digest is weekly narrative, inbox is low-latency |
| Substrate | Scheduled skill via `soleur:schedule` (GitHub Actions) | KB files on disk; lowest code; matches issue intent; avoids Inngest KB-not-in-container trap |
| Delivery channel | Private GitHub issue | First-party, no new processor, GitHub API already allowlisted |
| Synthesis | Claude (in-Action session) + deterministic fallback | Never a silently blank week; fallback output is a first-class product surface |
| Secret/PII gate | `redact-sentinel.sh` as pre-post gate, block on non-zero exit | Aggregated private data → wrong channel is the brand-critical failure mode |
| Incident source | Resolved, post-redaction PIRs only; summaries + links | Reading raw incident state would bypass the redaction gate (CLO) |
| Voice | Calm chief-of-staff brief; candid (names costs/incidents plainly) | NOT the community digest's promotional brand voice |
| Editorial rule | Every line answers "so what does this mean for me?" or it's cut | Kills the "vanity report" failure mode (CMO) |
| Read-signal gate | Define a falsifiable read/acted-on signal before expanding sections | Write-mostly-artifact learning: a weekly report nobody reads compounds debt |

## Open Questions

1. **Read/consumption signal** — what concretely counts as "the operator read/acted on it"? (issue
   reaction, a reply, a follow-up action). Decide at plan time; gate section expansion on it.
2. **Liveness/failure alerting** — GitHub Actions lacks the Inngest Sentry-heartbeat. What's the
   minimum acceptable "the digest silently stopped" detector for the Actions substrate? (Action
   failure notification + optional lightweight heartbeat post.)
3. **"Money changes" diff mechanics** — exact git-diff window/format over `expenses.md` to surface
   only *this week's* ledger deltas in plain language.
4. **Action-needed ↔ inbox boundary** — confirm with #5103 owner that the digest's weekly recap reads
   the same `action-required` signal the inbox uses, so they never disagree.
5. **`action-required` label registration** — research found the label is applied ad-hoc by automation,
   not registered. Confirm/register it so the digest's query is reliable.

## Domain Assessments

**Assessed:** Product, Engineering, Legal, Marketing (Operations, Sales, Finance, Support not relevant)

### Product (CPO)
**Summary:** Genuinely distinct from the community digest and uncovered — build it as a thin
synthesizer. V1 = built/money/incidents; cut content-published (campaign-calendar) and coordinate
action-needed with the already-shipped operator inbox (#5103). Gate section expansion on a measured
read-rate to avoid an unread report.

### Engineering (CTO)
**Summary:** Reuse the weekly-digest scaffold (LLM + deterministic fallback + failure alerting), but
run as a scheduled skill because `knowledge-base/` is not in the web-platform container. Delivery via
private GitHub issue (no new egress, outside Tier-2). Run `redact-sentinel.sh` as a hard pre-post gate;
every section needs its own deterministic degradation.

### Legal (CLO)
**Summary:** Permitted with guardrails. Private GitHub issue is the lowest-risk (first-party) channel;
email/Discord are third-party processors. Load-bearing guardrails: (1) first-party default + per-channel
ack before any third-party channel; (2) incident content from committed post-redaction PIRs only;
(3) summaries + reference-links, no raw records or PII fields.

### Marketing (CMO)
**Summary:** Calm chief-of-staff register, NOT the community digest's promotional brand voice — its
value is candor (names costs/incidents plainly). Reuse distribution-content frontmatter as the source
of truth for any content section. Editorial rule that prevents a vanity report: every line states a
business consequence or an action, or it is cut.

## User-Brand Impact

- **Artifacts:** the aggregated private digest itself (financials + vendor names + incident detail +
  open decisions concentrated into ONE document) and its delivery target.
- **Vectors (operator endorsed all risk vectors → USER_BRAND_CRITICAL):**
  1. **Private business data → wrong/public channel.** Mitigations: private-GitHub-issue-only channel
     (no shared webhook helper with the public digest; no fallback channel); `redact-sentinel.sh`
     pre-post gate blocking on non-zero exit.
  2. **Silent failure / false calm.** A silently-stopped digest makes the operator believe they're
     caught up when they're not. Mitigations: deterministic fallback (never blank); Action-failure
     alert + liveness detector (Open Question #2).
  3. **Incident/PII over-exposure.** Mitigations: post-redaction PIR summaries only; summaries +
     links, no raw records; PII-scrub LLM input *before* truncation and before any quantified regex
     (slice-before-regex, per the release-digest review-catch learning).
- **Threshold:** `single-user incident`.

## Productize Candidate

This brainstorm's output **is** the reusable artifact (a new `soleur:operator-digest` skill +
scheduled workflow), so no separate productize follow-up is needed.

## Carry-Forward Engineering Constraints (from learnings)

- Fallback output is a first-class product surface — assert its content quality, not just that it posts.
- Fence-strip LLM JSON via `extractModelJson` (`server/model-json.ts`) at the parse site.
- Slice raw input *before* any quantified PII regex (O(n²) stall risk).
- No runtime `knowledge-base/` disk reads from the web-platform container (moot here — skill substrate
  has the repo, but relevant if the Inngest path is ever revisited).
- Add a positive happy-path test that fails when the LLM call is silently broken.
