---
date: 2026-09-18
topic: Apply WikiSkill (arXiv 2608.27454) to Soleur's compounding loop — pattern wiki, proposal ledger, gated skill creation
lane: cross-domain
brand_survival_threshold: single-user incident
source: https://arxiv.org/abs/2608.27454
source_license: CC BY 4.0 (verified 2026-09-18 on the arXiv abstract page)
related: ['#6037 (closed)', '#6038 (open)', '#6102 (open)', '#8274 (open)', 'ADR-069', 'ADR-091', 'ADR-092']
---

# Brainstorm: WikiSkill-style Skill Evolution for Soleur

## What We're Building

A **three-phase upgrade of Soleur's existing compounding loop**, adopting the structure of
Google Research's WikiSkill (arXiv 2608.27454, 2026-08-27, CC BY 4.0):

- **Phase 1 — make the loop work and be visible.** Repair the silent proposer
  (`cron-compound-promote`), fix the diff-allowlist bypass (#8274), add a two-tier
  **pattern wiki** (`patterns/` + a one-line-per-pattern index) over the existing learnings
  corpus, and add a machine-written **proposal ledger** recording accepted *and rejected*
  proposals that the proposer must read before proposing.
- **Phase 2 — gated new-skill creation.** Free description-budget headroom, then let the
  proposer open a draft PR that *creates* a skill (markdown-only, with `PURPOSE.md`
  provenance) when a mature pattern has no skill that owns it.
- **Phase 3 — concise skills.** Move `**Why:**` rationale and learning citations out of the
  largest SKILL.md files into `PURPOSE.md`, one skill per PR.

Each phase must prove itself before the next starts. Every phase keeps the existing
human-reviewed draft-PR gate; nothing auto-merges.

## Why This Approach

**Soleur is not greenfield.** The 2026-07-05 audit (#6037) already mapped Self-Harness/HarnessX
onto Soleur and shipped the read-only weakness-miner. What WikiSkill adds that Soleur lacks is
the *persistent, deduplicated knowledge layer between raw experience and executable skills* —
the paper's ablation attributes +15.0 points average (48.7% → 63.7%) to exactly that layer.

**Four findings from this session's research, each verified, shaped the scope:**

1. **The proposer runs, spends real money, and produces nothing observable.** `promotion-config.yml`
   has `enabled: true` since 2026-07-06; `promotion-log.md` has **zero rows**; `gh pr list` finds
   **no** `self-healing/auto` PR or issue ever. Better Stack shows the 2026-09-13 run made one
   Sonnet call with **516,512 input tokens / 7,623 output tokens** (`SOLEUR_CLAUDE_COST`,
   `id: cron-compound-promote`). Sentry has **0** events for `feature:cron-compound-promote` in
   90d (control query `has:feature` returns live rows, so the channel works — the silence is
   real, not a broken query). Every refusal marker (`target-path-refused`, `diff-path-refused`,
   `byte-budget-overflow`, `git-apply-check-failed`, `agents-core-hr-rule-edit-refused`,
   `anthropic-response-truncated`) returns **0** hits over ~83 days; only one `Empty Anthropic
   response` was found. **The zero-cluster and completed paths log no outcome at all**, so the
   reason for zero output is *not currently knowable*. This refutes the CTO's hypothesis that
   the handler errors on every run — it does not error; it exits quietly.
2. **The corpus is the input, and it is enormous.** `collect-corpus` sends the first 10 lines of
   every non-archived learning — **2,309 files** (`git ls-files knowledge-base/project/learnings
   | wc -l`) — in a single message. The pattern index WikiSkill prescribes is ~50× smaller and is
   what the paper's ReAct proposer actually reads (index first, then pages on demand).
3. **The same failure class is re-documented every session.** The 2026-09-13 `weakness-digest.md`
   shows **15 learnings in one week** in a single "guards + mutation-testing" cluster, 12 in
   "mutation-testing + vacuity", 8 in "guards + vacuity". WikiSkill's Wiki Maintainer is
   explicitly forbidden from this ("do NOT create duplicate patterns — update existing ones with
   new evidence" via append/replace/insert_after patch ops).
4. **Rejected proposals are not retained.** The paper's `skill-impact.md` is written
   *programmatically by the harness*, holds the full rejected proposal, and the case study shows
   a rejection at iteration 0 steering the accepted skill at iteration 1. Soleur's
   `promotion-log.md` stores a hash and `pending` — no diff, no outcome — and the live decision is
   derived at read time from PR state, which nothing automated reads.

**Why phased over all-at-once:** skill creation (Phase 2) is worthless until the proposer
produces anything at all, and dangerous while #8274 is open and the description budget is at
**2,442 / 2,442 words — zero headroom** (`plugins/soleur/test/components.test.ts:21`; measured
98 skills, 2,442 words). Phase gates make that ordering structural rather than aspirational.

**Why full backfill (operator decision):** two-tier alone leaves the 2,309 historical learnings
un-indexed, so the proposer's new input would cover only new patterns. The operator chose
complete coverage over migration safety; the wrong-merge risk is contained by making the backfill
its own reviewed phase (chunked batches, human-reviewed, learnings never deleted or rewritten —
pattern pages only *link* to them, so a bad merge is repaired by editing one pattern page).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | **2+ phased** (full port with de-risking, 3 gated phases) | Gets real skill creation without taking on the risks up front. |
| Wiki model | **Two-tier + full backfill** | Learnings stay write-once per-session evidence (raw layer); `patterns/` holds one page per pattern with root cause + fix + evidence links. Backfill gives day-one coverage. |
| Backfill safety | Own reviewed phase; chunked; **learnings are never deleted or edited** | A wrong merge costs one pattern-page edit, not lost provenance. |
| Proposer input | **Pattern index + on-demand page reads**, replacing the 2,309-file corpus dump | Matches the paper's ReAct proposer; ~50× smaller than the measured 516k-token prompt. |
| Proposal ledger | **Machine-written, append-only**, holds the diff + outcome incl. **rejections**; proposer MUST read it first | The paper's `skill-impact.md`; preserves the existing non-repudiation property of `promotion-log.md`. |
| Observability | `SOLEUR_COMPOUND_PROMOTE_OUTCOME` on **every** run (status, cluster count, each refusal reason) + Sentry alert after 4 zero-output weeks | Today the zero-output path is silent; a loop you cannot observe cannot be tuned. Cites `hr-no-dashboard-eyeball-pull-data-yourself`. |
| #8274 | **Fix in Phase 1**, before any widening | The allowlist is bypassable via `git apply -p1` prefix stripping; Phase 2 *widens* that allowlist to new skill dirs. |
| Skill creation | Phase 2 only. Markdown-only (no `scripts/`), `PURPOSE.md` required, `skill-security-scan` in the pipeline, **net ≤ 0 description words** (trim bundled in the same PR) | Budget is at zero; auto-authored executable code is the risk class we refuse. |
| "Prefer patch" | A create proposal must name the nearest existing skill and justify not patching it; every create emits merge/retire candidates | The paper's own rule; guards the 98-skill discoverability surface. |
| Validation gate | Classifier blocks keep the strict eval gate (ADR-069). Procedural skills get a **lagging recurrence gate**: if the targeted pattern page gains new evidence within ~4 weeks of merge, the ledger marks the change **ineffective** | Soleur has no train/val split for procedural skills; the paper's strict-improvement rule cannot apply. The paper itself flags that strict gating rejects neutral enablers. |
| Hard rules | Unchanged: ADR-092 WORM acks + `diffRemovesHardRule`; new skills may not restate or relax `hr-*` | Goodhart containment stays where it was proven. |
| Raw layer | **Not committed.** If session traces are ever retained they stay local, gitignored, expiring, operator-repo only — no tenant or alpha-tester sources | CLO P1 (PA-31 §(g)(8): a ReAct trace reader has no prompt-assembly chokepoint to scrub). |
| Paper reuse | Adapt prompts with **CC BY 4.0 attribution** in the ADR and each `PURPOSE.md` | License verified live on the arXiv abstract page, 2026-09-18. |
| Positioning | "Soleur got sharper", never "your workspace got smarter" | Improvement is global-plugin, not per-tenant; possessive framing is a deceptive-implication risk (2026-07-06 learning). |
| North-star metric | **Recurrence of a failure class after a fix targets it**, not skills created | Skill count is a vanity metric; the 15-learning cluster is the case to track. |
| Visual design | N/A — no UI surface (harness/CI/knowledge-base infra only) | Phase 3.55 trigger boundary. |

## Open Questions (resolve at plan time)

- **Where `patterns/` lives** — `knowledge-base/project/patterns/` vs. inside `learnings/`. Affects
  INDEX.md (ADR-174 exclusions) and every existing link.
- **Who maintains pattern pages** — `/compound` upserts inline at session end (has the context),
  a weekly cron reconciles (catches unlinked learnings and proposes merges), or both. Lean: both.
- **Backfill batching and review unit** — how many learnings per batch, and what the reviewer
  actually checks (merge correctness vs. index-line quality).
- **Pattern maturity threshold for a create proposal** — the paper uses ≥5 sources for a cluster;
  is "no skill owns this pattern" judged by the model, by grep, or by a maintained owner field?
- **Where the description-trim headroom comes from** — a one-time pass over the 98 descriptions,
  or per-proposal trims only.
- **Whether the zero-output cause is cluster-threshold or guard-refusal** — Phase 1's outcome
  marker answers this on the first run; the plan should not guess it beforehand.

## User-Brand Impact

- **Artifact:** the pattern-wiki layer + proposal ledger + the gated auto-proposer that can create
  skills in the public `plugins/soleur/` surface.
- **Vector:** a proposer-authored skill or rule carrying leaked content (a learning's quoted secret
  or personal data) into every installed copy of the plugin, or silently weakening a guardrail that
  exists to protect a user's repo — published copies cannot be recalled.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). Controls: the human-reviewed draft-PR gate is
retained in every phase; auto-created skills are markdown-only and pass `skill-security-scan`;
the PII pre-pass extends to pattern pages; ADR-092 WORM acks and `diffRemovesHardRule` stay in
force; #8274 is fixed *before* the allowlist is widened; the raw layer never leaves the operator's
machine and never sources tenant data.

## Domain Assessments

**Assessed:** Product (CPO), Legal (CLO), Engineering (CTO + repo-research + learnings-researcher).
Marketing, Operations, Sales, Finance, Support — not relevant (internal harness infra; the
founder-facing changelog stays deferred under #6102).

### Product

**Summary:** Beneficiary is the operator's own harness, not tenant workspaces —
`cron-compound-promote` clones the Soleur repo and nothing scopes skills per workspace, so
"your workspace got smarter" is off-limits and "Soleur got sharper" is the honest framing. The
first step must be diagnosis, not a build: the loop has produced 0 PRs in ~10 weeks, so a new
layer on top of a silent producer adds nothing. North star should be recurrence-after-fix, with
accepted proposals per month as the leading indicator and net skill count/description budget as a
guardrail. The paper's cross-model transfer result (smaller model + skills beating a larger model
without) is a real margin lever but must be reproduced on Soleur's own evals before it becomes a
claim.

### Legal

**Summary:** The method, the wiki, the proposer and the gate are covered by the existing register
provided they read only already-committed content. The one hard constraint is the paper's raw
layer: PA-31 §(g)(8) records that a ReAct trace reader has **no prompt-assembly chokepoint**, so
`cron-compound-promote`'s PII pre-pass would not carry over; session traces additionally hold
Doppler reads, issue bodies, inbound mail (PA-27) and Discord content (PA-32), and Anthropic
retention is 30 days with `zero_retention_amendment: unsigned`. Committing traces write-once to a
public repo also conflicts with Art. 5(1)(e) and Art. 17. Therefore: raw layer local, gitignored,
expiring, operator-repo only; tenant/alpha-tester sources are barred by PA-34 control C1; run
`/soleur:gdpr-gate` at plan time **only if** the design retains or transmits raw traces. Paper
ideas are not copyrightable (Directive 2009/24 Art. 1(2)) and the arXiv listing is **CC BY 4.0**
(verified), so prompt text may be adapted with attribution. Auto-created skills carry no statutory
disclosure duty (T&C §7 covers AI output); the real exposure is content leaking into every
installed copy, mitigated by the human gate plus provenance records.

### Engineering

**Summary:** The top gap is not a missing component — it is that the only machine writer produces
nothing and cannot be observed. Second is pattern consolidation (a new file per session rather
than evidence appended to a pattern page), which also shrinks the proposer's input ~50×. Skill
creation should wait for both. A machine-written ledger including rejected proposals is small,
low-risk, and fits the existing append-only non-repudiation contract. Procedural skills have no
train/val split, so the honest gate is human-merged draft PR + deterministic lints (ADR-092 hash
acks, byte budget) + a lagging recurrence check. Risks: Goodhart (ADR-092 concedes the eval gate
measures fixture pass-rate, not guardrail coverage), #8274 open, zero description-budget headroom,
skill-count bloat. The paper's runtime-wiki-access finding maps only partially — Soleur's closest
equivalent is `learnings-researcher` being spawned at plan/brainstorm time, not the inline `Why:`
prose; the prose is nonetheless bloat (ship 2,833 lines vs the paper's 45–140), which makes
Phase 3 a token/clarity cleanup rather than a claimed quality win.

## Capability Gaps

- **No pattern-consolidation primitive ("Wiki Maintainer") exists.** Evidence: `git ls-files`
  sweep for `patterns/` under `knowledge-base/project/` returns nothing; `compound-capture`
  offers an "update existing" branch but defaults to creating a new file
  (`plugins/soleur/skills/compound-capture/SKILL.md`); `weakness-digest.md` re-derives tag
  co-occurrence clusters weekly and is stateless. That missing primitive is Phase 1's core.
- **No provenance record links a skill to its motivating evidence.** Evidence:
  `git ls-files 'plugins/soleur/skills/*/PURPOSE.md'` returns zero rows across 98 skills.
- **No machine-readable record of rejected improvement proposals.** Evidence:
  `knowledge-base/project/learnings/promotion-log.md` has zero rows below its marker and its
  documented schema stores `pending` only, with the live decision derived at read time.
- **The proposer's outcome is unobservable.** Evidence: the `no-qualifying-clusters` and
  `completed` return paths in `cron-compound-promote.ts` emit only a Sentry heartbeat with
  `ok: true` and no marker; all refusal markers measured 0 over ~83 days.

## Session Errors

- **A subagent hypothesis was carried as fact until re-derived.** The CTO reported the promoter
  "is probably failing on every run" (context-window overflow → `handler-top-level`). Direct
  telemetry refuted it: 0 Sentry events for `feature:cron-compound-promote` in 90d against a
  working control query, and a Better Stack cost marker showing a completed 516,512-token call.
  The agent labelled it a hypothesis; the fix is that the brainstorm re-derived it before it
  reached the spec (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **`repo-research-analyst` reported facts that did not survive re-derivation** — it described the
  promoter as "ReAct-style" (it is a single structured-output call) and gave a learnings count of
  2,309 that happened to match, alongside a "35/100 skills" figure derived by a different command
  than the one it quoted. Counts used in this document were re-derived here.
- **An empty telemetry result was nearly read as evidence of absence.** The first Sentry query
  returned `[]`; a `has:feature` control query confirmed the channel was live before the silence
  was treated as a finding.
