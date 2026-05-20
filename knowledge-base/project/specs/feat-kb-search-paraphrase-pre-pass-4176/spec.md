---
feature: feat-kb-search-paraphrase-pre-pass-4176
issue: 4176
parent_issue: 4119
date: 2026-05-20
status: ready-for-plan
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-20-kb-search-paraphrase-pre-pass-brainstorm.md
draft_pr: 4183
branch: feat-kb-search-paraphrase-pre-pass-4176
---

# Spec: kb-search Stage 2 — LLM paraphrase pre-pass

## Problem Statement

Stage 1 of #4119 (PR #4156, merged 2026-05-20) closed the structural displacement bug in `kb-search` (cap-split + learnings-only tier-1 sub-index + frontmatter backfill). Post-Stage-1: `R@5(heavy, kb-search) = 0.2947` vs grep ceiling `0.3025`, `gap_skill_roi = −0.008` (at grep parity). The remaining gap to the 0.4 ladder threshold is bounded by grep's own semantic ceiling at heavy paraphrase. No keyword-strategy tuning (IDF, stopwords, scoring) can exceed grep's ceiling; the published #4119 ladder routes `< 0.3 → Stage 2 (LLM paraphrase pre-pass)`.

`/compound` is producing knowledge the lookup mechanism cannot surface ~70% of the time on heavy-paraphrase queries. The compounding loop is silently leaking on the hardest semantic-divergence cases.

## Goals

1. Recover `R@5(heavy, kb-search) ≥ 0.4` AND keep identity/light R@5 from regressing > 0.02 vs Stage 1 baseline.
2. Add an LLM paraphrase pre-pass to `kb-search` that fires only when baseline grep returns `< 5` candidate paths (adaptive routing).
3. Keep runtime marginal API cost at ~$0 (agent-inline paraphrasing — Option C) while preserving deterministic bench measurement via Haiku.
4. Ship complete operator-trust mitigation bundle (`--no-paraphrase` flag, env-var hard caps, sensitive-query regex guard, `~/.cache/soleur/kb-search/` cache contract) so a future fork to out-of-process calls cannot bypass the published commitments.

## Non-Goals

- **Embeddings / vector index / RAG.** That is Stage 3, reachable only if Stage 2 misses the gate. Stage 3 REQUIRES `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` per Stage 1 plan FR7+TR6 — DO NOT silently implement embeddings without the ADR.
- **IDF / stopword scoring tweaks** (was Stage 1.5). Moot post-Stage-1 because kb-search ≈ grep at every paraphrase level; scoring tweaks cannot exceed grep's heavy-paraphrase ceiling (~0.30).
- **Growing `kb-search/SKILL.md` frontmatter `description:` field.** Cumulative plugin-wide description budget is at 1847/1800 (−47 words). Body sections may grow; description must stay at 26 words unless the plan author lands a ≥47-word sibling-trim sub-plan.
- **Repo-tracked paraphrase cache.** Cache is operator-local under `~/.cache/soleur/`; `.gitignore` covers it. The bench's `/tmp/kb-bench-*/paraphrases.ndjson` operator-supplied path stays operator-only.
- **Out-of-process runtime Haiku calls** (Option B). Recorded as a possible future fork; Stage 2 ships Option C (agent-inline runtime + bench-only Haiku).
- **Commenting on #4042 to "unblock"**. #4042 is already CLOSED (2026-05-20 via PR #4094, independent path through pre-committed ladder Branch B/C). Note in PR body to avoid stale-comment confusion.
- **Mirroring paraphrase-fallback events to Sentry for the runtime path.** kb-search is a developer-tool skill; `cq-silent-fallback-must-mirror-to-sentry` rule body targets TS production surfaces. Bash stderr warning satisfies the rule's non-silent intent. The bench side (gate surface) does carry Sentry mirroring via `mirrorWithDebounce` errorClass `kb-search:paraphrase-fallback`.

## Functional Requirements

- **FR1**: `kb-search` SKILL.md adds **Phase 2.5: Paraphrase Pre-Pass** between Phase 2 (Facet Validation) and Phase 3 (Keyword Search). When (a) `$KEYWORD` is non-empty AND (b) baseline two-tier grep returns `< KB_SEARCH_PARAPHRASE_HIT_THRESHOLD` (default 5) candidate paths AND (c) `--no-paraphrase` was not passed AND (d) `$KEYWORD` does not match the sensitive-query regex, the skill instructs the executing agent to generate 3-5 short paraphrase variants of `$KEYWORD`, runs the existing two-tier grep against each variant, unions the results, dedupes by path, and ranks by union-hit-count. The existing 8 tier-1 + 12 tier-2 cap-split applies to the merged result set.
- **FR2**: `--no-paraphrase` flag (operator escape hatch). When present, Phase 2.5 is skipped entirely. Documented in SKILL.md `## Arguments` and `## Privacy & Cost` sections.
- **FR3**: **Sensitive-query regex guard**. Before any LLM forward, kb-search refuses (with remediation message) if `$KEYWORD` matches `(SECRET|TOKEN|KEY|PASSWORD|sk-[a-zA-Z0-9]+|dsn=)` (case-insensitive). Per the 2026-05-06 bang-prefix-leaks-secrets learning. Operator can override with `--no-paraphrase` (which also skips the LLM forward, sidestepping the guard).
- **FR4**: **Adaptive routing**. Paraphrase pre-pass fires only when baseline two-tier grep returns `< KB_SEARCH_PARAPHRASE_HIT_THRESHOLD` (default 5) candidate paths. Tunable via env var.
- **FR5**: **Hard caps (published commitments, fail-closed)**: `KB_SEARCH_MAX_PARAPHRASE_CALLS` (default 200/session), `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD` (default $10). Breach emits stderr notification and falls back to baseline grep. Caps don't fire under Option C runtime (no separate billable event) but are documented as forward-compatible commitments.
- **FR6**: **Paraphrase cache contract**. Local NDJSON at `~/.cache/soleur/kb-search/paraphrases.ndjson`, keyed by `sha256(canonicalized-query)`. 14-day TTL. `--clear-cache` subcommand. `chmod 700` operator-owned. `.gitignore` covers the path. `--no-paraphrase` bypasses cache writes.
- **FR7**: **Bench-side `kbsearch_rank()` lockstep** (TR2 from Stage 1). `scripts/learning-retrieval-bench.sh` extends `kbsearch_rank()` (line 494) to emulate the union-of-paraphrases strategy: call `anthropic_paraphrase()` (line 325) to generate variants, run the existing two-tier rank logic per variant, union/dedupe by path, return rank of target. The `--cache-paraphrases <path>` flag (already exists at line 65) lets reruns hit the existing `/tmp/kb-bench-2026-05-20/paraphrases.ndjson` (1147 paraphrases) for cheap re-execution.
- **FR8**: **Per-bucket bench breakdown**. JSON output schema adds `r5_identity`, `r5_light`, `r5_heavy` per row (in addition to the existing combined R@5). Identity/light must not regress > 0.02 vs Stage 1 baseline post-merge. Optional: per-paraphrase-variant rank attribution.
- **FR9**: **Stderr fallback warning** (NOT silent) when paraphrase generation fails (rate limit, network, refusal). Format: `kb-search: paraphrase generation unavailable — falling back to baseline grep`. Bench side mirrors to Sentry via `mirrorWithDebounce` errorClass `kb-search:paraphrase-fallback`.
- **FR10**: **Ladder triage post-bench-rerun** (operator-acked $3 + ~70min):
  - `R@5(heavy, kb-search) ≥ 0.4` AND identity/light R@5 not regressing > 0.02 → close #4176 + close #4119.
  - `R@5(heavy, kb-search) < 0.4` OR identity/light regress > 0.02 → file Stage 3 (embeddings/RAG) deferred-tracking issue with explicit ADR-trigger note (`/soleur:architecture create 'Adopt embeddings-based KB retrieval'` REQUIRED before any Stage 3 implementation).
- **FR11**: **14-day actuals validation issue** filed at PR-ready time, tracking paraphrase invocation count per session + hit rate of the `<5` adaptive-routing gate + observed quality variance, to verify the $0-marginal-runtime envelope against real telemetry.

## Technical Requirements

- **TR1**: **Option C runtime mechanism**: SKILL.md Phase 2.5 instructs the executing agent to generate paraphrases inline. No separate Anthropic API call from the skill itself at runtime. Quality varies by session model; bench (Haiku) is the fair upper bound.
- **TR2**: **Lockstep change**: `plugins/soleur/skills/kb-search/SKILL.md` AND `scripts/learning-retrieval-bench.sh:kbsearch_rank` MUST update in the same commit. Per Stage 1 TR2 pattern. CI assertion (added in this PR): grep both files for a shared strategy-shape token (e.g., `# stage-2-paraphrase-union-v1`), fail if only one has it. Per the 2026-05-14 plan-prescribed-runtime-shapes-must-be-grepped learning.
- **TR3**: **New synthesized self-test fixture** in `learning-retrieval-bench.sh --self-test`: a learning whose identity query has zero token overlap with content (e.g., target file content "database connection pool exhaustion under burst load", identity query "ORM saturating worker pool"). Baseline grep MUST fail (rank=null); paraphrase pre-pass MUST recover the target. Per `cq-test-fixtures-synthesized-only`.
- **TR4**: **Cache invalidation on paraphrase failure**: cache writes only on successful paraphrase generation. Partial / `(API_ERROR)` outputs (per existing bench sentinel at line 359) do not land in cache. Bench coverage check (line 1064+) re-runs cleanly against the existing 1147-entry cache.
- **TR5**: **Bench cost ceiling**: `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-2026-05-20/paraphrases.ndjson` runs against the cached paraphrases (cache HIT, sub-second per the existing cache flag) for re-measurement. Cold rerun (cache MISS) is ~$3 + ~70min and is operator-acked before invocation. The bench script's existing `--confirm` flag is the ack gate.
- **TR6**: **PR body disclosure** (per `hr-autonomous-loop-skill-api-budget-disclosure`) carries the 7-item CLO checklist: (a) runtime API budget envelope ($0 marginal under Option C); (b) bench gate cost ($3/rerun, operator-acked); (c) new outbound-data-surface statement (Option C runtime adds NO new surface; bench Haiku call is the only outbound use) + Anthropic ToS link; (d) `--no-paraphrase` opt-out documentation; (e) operator-hygiene reaffirmation (link `hr-never-paste-secrets-via-bang-prefix`); (f) cache location/TTL/`.gitignore`; (g) confidentiality-not-GDPR framing + re-evaluation trigger (escalate to `multi-user incident` if kb-search ever consumes end-user input).
- **TR7**: **Verify-before-relaunch discipline**: if the bench is started via `run_in_background`, NEVER relaunch on pgrep-empty + stale-log-mtime alone. Per `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md` + `plugins/soleur/skills/work/SKILL.md` Common Pitfalls.

## Domain Review (carry-forward)

Per the brainstorm document. CTO + CPO + CLO triad assessment summary preserved verbatim — plan author should NOT re-spawn the triad unless scope materially changes.

- **Engineering (CTO):** Recommends Option C. TR2 lockstep satisfied by decoupling. No capability gaps; reuse `anthropic_paraphrase()` (bench-side) + `kbsearch_rank()` (extend, don't replace) + NDJSON cache pattern. Architecture-decision worth recording via `/soleur:architecture create`.
- **Product (CPO):** Confirms threshold `single-user incident`. Premise correction: only one explicit kb-search programmatic caller (compound-capture); `~100 invocations/session` is modeled-on-modeled. Non-negotiable: `--no-paraphrase`, adaptive `<5` routing, per-bucket R@5 with `> 0.02` regression budget, env-var hard caps.
- **Legal (CLO):** GDPR/HIPAA not applicable to runtime path. Anthropic ToS verified (no-training, 30-day default retention, 2-year abuse-monitoring window if flagged, ZDR available by agreement, Soleur has no ZDR addendum on file). `--no-paraphrase` required as defense-in-depth + operator-trust mechanism. Cache at `~/.cache/soleur/` acceptable with TTL + chmod + `--clear-cache` + `.gitignore`. Repo-tracked cache: hard no. PR body 7-item disclosure required.

## Capability Gaps (carry-forward to plan)

- **Per-session API-call cap precedent**: Soleur ships zero existing skills/scripts with such a cap. Stage 2 is first. Required by ship per CPO non-negotiable hard caps.
- **Description budget headroom**: cumulative is at −47 words. Plan author must NOT grow `kb-search/SKILL.md` `description:` field, OR must include ≥47-word sibling-trim sub-plan.

## Acceptance (mirror to PR body checklist)

- [ ] SKILL.md Phase 2.5 added with FR1-FR6 implementation; `--no-paraphrase` flag honored; sensitive-query regex guard wired; adaptive routing at default threshold 5; cache contract at `~/.cache/soleur/kb-search/` + `.gitignore` updated.
- [ ] `learning-retrieval-bench.sh:kbsearch_rank` extended for union-of-paraphrases in lockstep (TR2). Shared strategy-shape token (e.g., `stage-2-paraphrase-union-v1`) in both files. CI assertion added.
- [ ] New synthesized self-test fixture demonstrating paraphrase pre-pass recovering a target whose identity query has zero token overlap with content. `bash scripts/learning-retrieval-bench.sh --self-test` passes.
- [ ] Per-bucket R@5 (identity/light/heavy) emitted to JSON.
- [ ] PR body 7-item CLO disclosure complete.
- [ ] Hard caps (`KB_SEARCH_MAX_PARAPHRASE_CALLS=200`, `KB_SEARCH_MAX_DAILY_PARAPHRASE_USD=$10`) documented in SKILL.md.
- [ ] Operator runs `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-2026-05-20/paraphrases.ndjson` (ack-gated). Results committed to `knowledge-base/project/learning-retrieval-metrics-<date>.json` + new `knowledge-base/project/learnings/<date>-retrieval-diagnostic-findings.md`.
- [ ] Ladder triage executed: close #4176 + #4119 (gate pass) OR file Stage 3 deferred-tracking issue with ADR-trigger note (gate miss).
- [ ] 14-day actuals validation issue filed.
