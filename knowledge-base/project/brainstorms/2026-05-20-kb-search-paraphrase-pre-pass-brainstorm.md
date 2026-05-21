---
date: 2026-05-20
topic: kb-search-paraphrase-pre-pass
issue: 4176
parent_issue: 4119
supersedes_decision_in: null
lane: cross-domain
brand_survival_threshold: single-user incident
status: decided
---

# kb-search Stage 2 — LLM paraphrase pre-pass

## What We're Building

A **paraphrase pre-pass** for the `kb-search` skill that recovers heavy-paraphrase recall to R@5 ≥ 0.4. When baseline keyword grep returns fewer than five candidate paths, the skill generates 3-5 short paraphrase variants of the operator query, runs the existing two-tier grep against each variant, unions the results, dedupes by path, and applies the existing cap-split (8 tier-1 + 12 tier-2).

Two surfaces change in lockstep (per Stage 1 TR2):

- `plugins/soleur/skills/kb-search/SKILL.md` — adds Phase 2.5 (paraphrase generation) between Phase 2 (facet validation) and Phase 3 (keyword search). **Runtime is agent-inline** — the executing session model generates the paraphrases as part of skill execution. No separate Anthropic API call at runtime.
- `scripts/learning-retrieval-bench.sh` — extends `kbsearch_rank()` to emulate the same union-of-paraphrases strategy. The bench-side LLM call remains `anthropic_paraphrase()` against Haiku, for reproducibility of the gate measurement.

This is **Option C** in the runtime fork: hybrid agent-inline runtime + bench-only Haiku. Decoupling lets the bench measure a deterministic Haiku-quality recall ceiling while runtime stays at zero marginal API spend.

## Why This Approach

Stage 1 closed the structural displacement bug (cap-split + learnings-only tier-1 sub-index). Post-Stage-1 numbers:

| | Pre-Stage-1 | Post-Stage-1 | Δ |
|---|---|---|---|
| R@5(heavy, kb-search) | 0.1331 | **0.2947** | +0.162 (+121%) |
| R@5(heavy, bare grep) | 0.3061 | 0.3025 | −0.004 |
| `gap_skill_roi` | −0.173 | **−0.008** | +0.165 |

`gap_skill_roi ≈ 0` means kb-search now performs at grep parity across all paraphrase intensities. The remaining gap to the published 0.4 ladder threshold is bounded by **grep's own semantic ceiling at heavy paraphrase** (~0.30). No tuning of the existing keyword strategy — IDF weights, stopword lists, scoring tweaks — can exceed grep's ceiling, because kb-search IS keyword grep with two-tier ordering. Stage 1.5 (IDF/stopword tune) is therefore moot at this point, which is consistent with the published #4119 ladder's `< 0.3 → Stage 2` branch (current R@5(heavy) = 0.2947 is inside that branch).

Semantic augmentation is the only path. LLM paraphrase pre-pass is the cheapest such intervention — it adds variant queries to expand grep's effective coverage without standing up new infra (embeddings + vector index = Stage 3 ADR-required).

Option C wins the runtime fork because:

- **Cost (`hr-autonomous-loop-skill-api-budget-disclosure`)**: agent-inline = ~$0 marginal runtime spend. The honest 95th-percentile daily figure is "$0 marginal" plus the one-shot bench cost ($3, operator-acked).
- **Lockstep (Stage 1 TR2)**: bench keeps `anthropic_paraphrase()` (deterministic Haiku → reproducible ladder); runtime varies by session model. The measured bench number is a fair *upper bound* on real-world recall — runtime can only do worse than bench, never silently better.
- **Audit story**: two budgets, two disclosures. PR body discloses bench-side $3/run + runtime $0 marginal cleanly.
- **Legal (CLO)**: Option A (agent-inline everywhere) is legally cleanest because no new outbound surface beyond existing session context. Option C inherits A's legal cleanliness for runtime while preserving the bench's reproducibility.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Operator confirmed all three named vectors (billing surprise + silent retrieval regression + query-leak / prompt exfil). Threshold: **single-user incident**.

### Worst-case incident narrative

Operator opens an autonomous loop (`/soleur:one-shot`, `/loop`) on a sensitive in-flight incident; the query string contains a literal customer name, an exfiltrated credential fragment, or an internal incident ID. The loop invokes kb-search 400+ times over an hour. Three failure modes compound:

1. **Query-leak** — if any future variant moves to Option B (out-of-process Haiku), the raw query lands in the Anthropic API logs and inside the 2-year abuse-monitoring window (`https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-personal-data`).
2. **Silent retrieval regression** — paraphrase variants degrade an identity-level query that already worked; the planning loop omits a prior-art file it would have surfaced without paraphrase; the resulting plan is subtly worse without any operator-visible signal.
3. **Billing surprise** — under Option B the unmeasured 95th-percentile envelope ($2.50-$5.00/day at 50 sessions) is a model on top of a model. An autonomous loop that breaches the per-session cap silently could rack up unexpected Anthropic spend; the invoice arrives 30 days later with no per-session ledger to reconstruct from.

### Mitigations (all required for ship)

- `--no-paraphrase` operator escape-hatch flag (skips Phase 2.5 entirely; symbolic under Option C but defense-in-depth if a future fork adds the out-of-process call).
- **Sensitive-query regex guard** before any LLM forward: refuse with remediation message if query matches `(SECRET|TOKEN|KEY|PASSWORD|sk-[a-zA-Z0-9]+|dsn=)`. Applies at the bench layer (Option C bench side); the runtime layer benefits from the same guard as defense-in-depth.
- **Adaptive routing**: paraphrase fires only when baseline grep returns `< 5` hits (tunable via `KB_SEARCH_PARAPHRASE_HIT_THRESHOLD`). Eliminates the silent-regression vector on identity/light queries that already work.
- **Per-bucket bench breakdown**: identity / light / heavy R@5 reported separately. Identity and light must not regress > 0.02 vs Stage 1 baseline. The R@5(heavy) ≥ 0.4 gate alone is insufficient — it cannot prove non-regression at the easier buckets.
- **Hard caps** (published as commitments even though they don't fire under Option C runtime — future-proofs against B): `KB_SEARCH_MAX_PARAPHRASE_CALLS=200` per session, `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD=$10`, fail-closed with stderr notification on breach.
- **Cache at `~/.cache/soleur/kb-search/`** (NDJSON keyed by sha256 of canonicalized query). 14-day TTL. `--clear-cache` subcommand. `chmod 700` operator-owned. `.gitignore` covers the path. `--no-paraphrase` bypasses cache writes.
- **Silent-fallback policy**: paraphrase generation failure → fallback to baseline grep + emit stderr warning ("paraphrase generation unavailable — falling back to baseline grep"). For the bench surface, mirror to Sentry with `mirrorWithDebounce` errorClass `kb-search:paraphrase-fallback` (per the 2026-05-13 mirror-debounce learning; cardinality is per-query × per-user).
- **PR body disclosures** (per `hr-autonomous-loop-skill-api-budget-disclosure`): runtime cost envelope ($0 marginal under Option C) + bench gate cost ($3/run, operator-acked) + opt-out flag + cache location + Anthropic ToS link + threshold re-evaluation trigger (if kb-search ever consumes end-user input, escalate to `multi-user incident`).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Strategy | **Stage 2 = LLM paraphrase pre-pass** (skip Stage 1.5) | Current `gap_skill_roi ≈ 0` (kb-search at grep parity) means no scoring tweak can exceed grep's heavy-paraphrase ceiling. The published #4119 ladder explicitly routes `< 0.3 → Stage 2`; we are at 0.2947. |
| Runtime mechanism | **Option C: agent-inline runtime + bench-only Haiku** | Triad consensus. Zero marginal runtime spend; bench preserves deterministic Haiku for reproducibility; runtime quality varies by session model but bench is the fair upper bound. |
| `--no-paraphrase` flag | **Yes, ships** | Defense-in-depth even under Option C. Symbolic at runtime (skips inline paraphrase step) but contractual under any future B variant. CLO + CPO + CTO consensus. |
| Adaptive routing | **Fire paraphrase only when baseline grep returns `< 5` hits** | Tunable via `KB_SEARCH_PARAPHRASE_HIT_THRESHOLD`. Eliminates silent-regression vector on identity/light queries. CTO + CPO consensus. |
| Sensitive-query regex guard | **Required** before any LLM forward | Pattern `(SECRET\|TOKEN\|KEY\|PASSWORD\|sk-[a-zA-Z0-9]+\|dsn=)` refuses with remediation. Per the 2026-05-06 bang-prefix-leaks-secrets learning. |
| Hard caps | **Ship full bundle**: `KB_SEARCH_MAX_PARAPHRASE_CALLS=200/session`, `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD=$10`, fail-closed | Future-proofs against any future fork that adds out-of-process calls. Published commitments. Capability gap: first Soleur skill with per-session API-call cap. |
| Cache location | **`~/.cache/soleur/kb-search/` NDJSON, 14-day TTL, `--clear-cache`, chmod 700, .gitignore** | Local-only, operator-confidential at rest. NOT committed to repo. Bench cache (`/tmp/kb-bench-2026-05-20/paraphrases.ndjson`) stays operator-supplied path; bench can warm the runtime cache. |
| Fallback policy | **Stderr warn + baseline grep**, NOT silent. Bench surface mirrors to Sentry via `mirrorWithDebounce` with errorClass `kb-search:paraphrase-fallback` | `cq-silent-fallback-must-mirror-to-sentry` rule body targets TS production surfaces; bash dev-tool stderr warn satisfies intent. Bench is the observability surface. |
| Per-bucket bench breakdown | **Add identity / light / heavy R@5 each to JSON output** | Identity/light must not regress > 0.02 vs Stage 1 baseline. The R@5(heavy) ≥ 0.4 single-number gate is insufficient. CTO + CPO consensus. |
| TR2 lockstep | **`SKILL.md` Phase 2.5 + `learning-retrieval-bench.sh:kbsearch_rank` change in same commit** | Stage 1 TR2 verbatim. CI assertion that greps the strategy-shape token in both files per the 2026-05-14 plan-prescribed-runtime-shapes learning. |
| New self-test fixture | **Synthesized: query with zero token overlap with target learning content** | Per `cq-test-fixtures-synthesized-only`. The fixture demonstrates the paraphrase pre-pass recovering a target whose identity query is semantically equivalent but lexically disjoint (e.g., target says "database connection pool exhaustion", query is "ORM saturating workers"). Catch the regression in `--self-test`, not the $3/70min full bench run. |
| Description budget | **Do NOT grow kb-search frontmatter `description:` field at plan time** | Cumulative plugin-wide description count is at 1847/1800 (**−47 words headroom**). Body sections may grow; description must stay at 26 words. |
| Workflow PAUSE | **Continue through plan + work, pause only at the bench rerun step** | Operator acks $3 + ~70min before `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-2026-05-20/paraphrases.ndjson`. Then ladder triage decides close-#4176-#4119 vs file-Stage-3. |

## Open Questions

- **Quality variance under Option C runtime**: session model paraphrases vary (Haiku < Sonnet < Opus). Bench measures Haiku-quality recall as the ceiling; runtime might do better OR worse on a given query. Accept the variance (CTO position) — bench is a fair upper bound. Revisit if 14-day actuals show meaningful runtime-vs-bench drift.
- **Sibling-trim sub-plan for description growth** (deferred to plan stage): if the plan author finds that a frontmatter description update is unavoidable (e.g., for discoverability of the paraphrase behavior), the plan must include a ≥47-word sibling-trim across other plugin skills. Default assumption: no description change needed; body sections + `--help` cover discoverability.
- **`--no-paraphrase` flag default value**: ON-by-default (paraphrase enabled, opt-out via flag) per triad consensus. Confirm at plan stage by checking the bang-prefix learning's threat model — operators carrying transient secrets should opt OUT, not opt IN.
- **Cache warming between bench and runtime**: bench writes to operator-supplied `--cache-paraphrases <path>` (existing flag). Runtime reads from `~/.cache/soleur/kb-search/`. Should bench optionally also write to the runtime cache path for cross-session reuse? Nice-to-have, deferred to a follow-up.
- **14-day actuals validation issue**: file at PR-ship time to verify the $0-marginal-runtime claim against real telemetry (paraphrase invocation count per session, hit rate of `<5` adaptive-routing gate, observed Haiku-paraphrase quality variance). Deferred-tracking issue per `wg-when-deferring-a-capability-create-a`.

## Acceptance Criteria

1. **Stage 2 land**: PR modifies `plugins/soleur/skills/kb-search/SKILL.md` to add Phase 2.5 (paraphrase generation) with agent-inline runtime + adaptive routing (`< 5` baseline hits) + `--no-paraphrase` flag + sensitive-query regex guard + cache contract at `~/.cache/soleur/kb-search/`; AND modifies `scripts/learning-retrieval-bench.sh:kbsearch_rank` in lockstep to emulate the union-of-paraphrases strategy bench-side.
2. **Hard caps shipped**: `KB_SEARCH_MAX_PARAPHRASE_CALLS=200` and `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD=$10` documented in SKILL.md with fail-closed semantics + stderr breach notification.
3. **Synthesized self-test fixture**: new fixture in `learning-retrieval-bench.sh --self-test` demonstrating paraphrase pre-pass recovering a target whose identity query has zero token overlap with content.
4. **Per-bucket bench breakdown**: JSON schema bump adds `r5_identity`, `r5_light`, `r5_heavy` per row (plus per-paraphrase-variant rank attribution).
5. **`--self-test` continues to pass** after the SKILL.md + bench changes.
6. **Bench rerun gate** (operator-acked, ~$3 + ~70min): `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-2026-05-20/paraphrases.ndjson` produces R@5 results committed to `knowledge-base/project/learning-retrieval-metrics-<date>.json` and a new `knowledge-base/project/learnings/<date>-retrieval-diagnostic-findings.md`.
7. **Ladder triage post-rerun**:
   - `R@5(heavy, kb-search) ≥ 0.4` AND identity/light R@5 do not regress > 0.02 → close #4176 + close #4119. (Note: #4042 already closed 2026-05-20 via PR #4094 — no `unblock` comment needed; superseded by independent shipping path.)
   - `R@5(heavy, kb-search) < 0.4` OR identity/light regress > 0.02 → keep #4176 + #4119 open; file Stage 3 (embeddings/RAG) deferred-tracking issue with ADR-trigger note: **REQUIRES `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` per Stage 1 plan FR7+TR6 — DO NOT silently implement embeddings without the ADR**.
8. **14-day actuals issue filed at PR ready**: follow-up to verify $0-marginal-runtime envelope + adaptive-routing hit rate + paraphrase quality variance against real telemetry.
9. **Premise-drift note**: #4042 (learnings-decay archive) is CLOSED as of 2026-05-20 via PR #4094 (independent path through pre-committed ladder Branch B/C). The ladder's "comment on #4042 to unblock" action is moot; record this in the PR body to avoid stale-comment confusion.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Per `USER_BRAND_CRITICAL=true`, mandatory triad. Marketing / Operations / Sales / Finance / Support — not relevant (developer-tool internal skill, no external surface).

### Engineering (CTO)

**Summary:** Recommends Option C (hybrid: agent-inline runtime + bench-only Haiku). Cost: ~$0 marginal runtime, bench preserves deterministic Haiku for reproducibility. TR2 lockstep satisfied by decoupling (not mirroring) — bench and runtime have different LLM-call shapes intentionally. Recommends adaptive routing (`< 5` baseline hits), stderr warn fallback (not Sentry — dev-tool surface), per-paraphrase rank breakdown in bench JSON. No capability gaps — every component exists: `anthropic_paraphrase()` at `scripts/learning-retrieval-bench.sh:325`, `kbsearch_rank()` at line 494, NDJSON cache pattern at lines 1044-1106. Flags an architecture-decision-worth-recording: the "runtime/bench LLM-call split" should land via `/soleur:architecture create` so future maintainers see the why.

### Product (CPO)

**Summary:** Confirms `single-user incident` threshold. Correcting premise: only one explicit programmatic caller of kb-search exists in the repo (`plugins/soleur/skills/compound-capture/SKILL.md:121-122`); other invocations are implicit via Skill tool / agent discovery, and the "~100 invocations/session" estimate in the issue body is modeled-on-modeled (treat as planning estimate, not ceiling). Requires `--no-paraphrase` flag + adaptive routing (`< 5` hits) + per-bucket R@5 breakdown (identity/light must not regress > 0.02). Non-negotiable hard caps: `KB_SEARCH_MAX_PARAPHRASE_CALLS=200/session`, `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD=$10`, fail-closed. Required follow-up: 14-day actuals issue to validate the unmeasured envelope against real telemetry.

### Legal (CLO)

**Summary:** GDPR/HIPAA not applicable to runtime path — operator queries are technical-developer input, not personal data of an identified natural person; B2B mentions ("Acme Corp last week") are contractual-confidentiality scope, not GDPR personal data. Anthropic Commercial Terms verified current (2026-05-20 fetch): no-training-on-customer-inputs, 30-day default retention, 2-year abuse-monitoring window if flagged, ZDR available by agreement but Soleur has no ZDR addendum on file. Confirms threshold `single-user incident`. `--no-paraphrase` flag required as defense-in-depth + operator-trust mechanism (NOT a legal must-have). Cache at `~/.cache/soleur/` acceptable with chmod 700 + 14-day TTL + `--clear-cache` subcommand + `.gitignore`; repo-tracked cache is hard-no. PR body must carry 7-item disclosure (API budget + outbound-data-surface statement + opt-out + operator-hygiene reaffirmation + cache location/TTL + confidentiality-not-GDPR framing + re-evaluation trigger). No statutory notice triggered.

## Capability Gaps

| Gap | What's missing | Domain | Why needed |
|---|---|---|---|
| Per-session API-call cap precedent | Soleur has **zero existing skills/scripts with a per-session API-call cap** (evidence: `grep -r 'MAX_SESSION\|SESSION_CAP\|--max-calls' scripts/ plugins/soleur/ .claude/hooks/` returns no matches; `AGENTS.md` lists `hr-autonomous-loop-skill-api-budget-disclosure` → core but governs disclosure not enforcement). Stage 2 is the first. | Engineering | Required by ship per CPO non-negotiable hard caps; published commitment even though Option C runtime doesn't trigger it. |
| Sibling-trim sub-plan headroom | Cumulative plugin-wide description count is **1847 / 1800 (−47 words)** per `grep -h 'description:' plugins/soleur/skills/*/SKILL.md \| wc -w`. Stage 2 cannot grow `kb-search`'s `description:` field without a ≥47-word sibling-trim sub-plan. | Engineering | Plan-stage budget checkpoint per `cq-skill-description-budget-headroom`. Default assumption: no description change. |

## Productize Candidates

None. The paraphrase pre-pass is a one-time `kb-search` lift, not a recurring work pattern that warrants its own skill.

## Session Errors

- **Premise-drift caught at Phase 1.0.5**: user input cited "comment on #4042 to unblock" as the Stage 2 success-path action, but `gh issue view 4042` shows state=CLOSED (2026-05-20 via PR #4094 — independent path through pre-committed ladder Branch B/C). The "unblock #4042" goal is superseded. Recorded in Acceptance Criteria item 9 and the brainstorm doc to avoid stale-comment confusion in the PR body.
- **CTO/research contradiction on description budget**: CTO said "headroom should not be a concern; verify before adding description text." Repo-research-analyst measured **−47 words headroom**. The research wins; CTO recommendation re-anchored to "no description-line growth at plan time."
- **Stage 1.5 collapse**: user input asserted "Stage 1.5 is moot — no scoring tweak on the current strategy can exceed grep at heavy." Confirmed against post-Stage-1 numbers: `gap_skill_roi = −0.008` means kb-search ≈ grep at every paraphrase intensity, so scoring tweaks can't exceed grep's own heavy-paraphrase ceiling (~0.30). Brainstorm proceeds directly to Stage 2 per the published #4119 ladder's `< 0.3 → Stage 2` branch (current 0.2947 < 0.30).

## Related

- Issue: #4176 (this brainstorm's tracking issue)
- Parent issue: #4119 (KB retrieval reopen; Stage 1 = PR #4156 merged 2026-05-20)
- Predecessor brainstorm (Stage 1, archived): `knowledge-base/project/brainstorms/archive/20260520-161017-2026-05-20-kb-retrieval-reopen-brainstorm.md`
- Original 2026-04-07 decision point: `knowledge-base/project/brainstorms/2026-04-07-kb-retrieval-improvement-brainstorm.md`
- Stage 1 post-merge diagnostics: `knowledge-base/project/learnings/2026-05-20-retrieval-diagnostic-findings.md`
- Stage 0 pre-Stage-1 diagnostics: `knowledge-base/project/learnings/2026-05-19-retrieval-diagnostic-findings.md`
- Closed sibling (independent path): #4042 (learnings auto-archive via R@K signal; closed 2026-05-20 via PR #4094)
- Stage 3 trigger (deferred): file `feat: kb-search Stage 3 — embeddings/RAG retrieval (ADR-trigger)` ONLY if bench rerun shows R@5(heavy) < 0.4 OR identity/light regress > 0.02. Stage 3 REQUIRES `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` per Stage 1 plan FR7+TR6.
- API-budget-disclosure precedent: `knowledge-base/project/brainstorms/2026-05-15-api-budget-preamble-backport-brainstorm.md` + `knowledge-base/project/plans/2026-05-15-feat-api-budget-preamble-backport-3819-plan.md` (`<decision_gate>` block template).
- Operator-secret-paste precedent: `knowledge-base/project/learnings/2026-05-06-bang-prefix-leaks-secrets-into-conversation-context.md`.
- Silent-fallback debounce pattern: `knowledge-base/project/learnings/2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`.
- LLM-output cache pattern: `knowledge-base/project/learnings/2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md`.
- Verify-before-relaunch (long-running bench): `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md`.
- Source SKILL: `plugins/soleur/skills/kb-search/SKILL.md`
- Source bench: `scripts/learning-retrieval-bench.sh` (lines 325 paraphrase gen, 494 kbsearch_rank, 1044-1106 NDJSON cache)
- Existing paraphrase cache (preserve): `/tmp/kb-bench-2026-05-20/paraphrases.ndjson` (1147 paraphrases from Stage 1 PR run)
- Draft PR: #4183
- Branch: `feat-kb-search-paraphrase-pre-pass-4176`
- Worktree: `.worktrees/feat-kb-search-paraphrase-pre-pass-4176`
