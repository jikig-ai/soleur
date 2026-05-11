---
date: 2026-05-11
issue: "#2720"
parent_issue: "#2718"
supersedes: "#421"
branch: feat-compound-promotion-loop
pr: "#3559"
status: brainstormed
user_brand_critical: true
---

# Compound Promotion Loop — Brainstorm

## What We're Building

A weekly GitHub Actions cron ("self-healing CI sweep") that reads the full `knowledge-base/project/learnings/` corpus, semantically clusters learnings by problem/root-cause via LLM inference, and opens a draft PR proposing a skill-instruction edit or AGENTS.md rule addition once a cluster reaches N=5 learnings.

The loop closes the gap between "we captured a learning" and "the learning is now codified," operationalizing AGENTS.md `wg-every-session-error-must-produce-either` (today, the gate relies on human vigilance during /compound).

The loop never auto-applies — every promotion lands as a draft PR with a provenance trailer; the operator merges or closes via normal PR review. Hooks are deferred to v2.

## Why This Approach

- **Reuses #421's design.** The Layer 2 weekly CI sweep was already designed during the 2026-03-03 self-healing-workflow brainstorm (issue #421, deferred until Layer 1 — Deviation Analyst — proved value). Layer 1 has been shipping in compound Phase 1.5 for two months. #421 is the prerequisite-met canonical mechanism; #2720 is the more recent re-framing from the 2026-05 claude-skills audit.
- **LLM clustering beats frontmatter counting.** Repo research showed only ~5.5% of existing learnings have structured frontmatter; the `rule_id` field only helps for already-codified rules (chicken-and-egg for promotion). Semantic clustering by LLM inference works on the existing corpus today without a schema migration.
- **Cron-only surface for v1.** An inline-at-/compound surface adds per-run LLM cost (clustering must repeat each session) and conflicts with the in-flow operator who is mid-task. Cron isolates the proposal cadence to once per week, aligning with the existing `rule-metrics-aggregate.yml` weekly schedule.
- **Skill + AGENTS.md targets only.** CPO and CTO both flagged hooks as highest blast radius (a bad PreToolUse hook can wedge every operator's session). The tier-gate (`cq-agents-md-tier-gate`) already prefers skill > AGENTS.md for placement when hooks aren't applicable. Hooks return in v2 with extra revert mechanism.
- **Manual-confirm via PR review.** Draft PR with the diff applied is the operator's existing review surface. No new UI to build; reviewers see the proposed edit in GitHub diff view exactly as they would a human PR.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Trigger:** weekly GitHub Actions cron (Sunday 00:00 UTC, aligning with existing `rule-metrics-aggregate.yml`) | Single source of truth for weekly automation. No per-/compound-run LLM cost. |
| 2 | **Counting:** LLM semantic clustering over the learnings corpus | ~94.5% of learnings lack structured frontmatter; tag-tuple grouping is too low-precision. Clustering surfaces same-root-cause learnings phrased differently across sessions. |
| 3 | **Threshold:** N=5 (cluster size) | CPO recommendation; reduces promotion-fatigue. Discoverability-exit principle: only promote what truly recurs across many sessions. |
| 4 | **Targets:** skill-instruction edits + AGENTS.md rule additions only | Hooks deferred to v2 due to blast radius. Skill = lowest blast. AGENTS.md = highest blast, gated by byte-cap suppression. |
| 5 | **Surface:** draft PR with the diff applied, labeled `self-healing/auto` | Reuses GitHub PR review as the operator gate. Provenance trailer in commit (Promoted-By, Source-Learnings, Threshold-Hit). |
| 6 | **Guardrails:** all four mandatory — byte-cap suppression for AGENTS.md (>37k → route to skill or skip), per-week PR cap (max 2/week), 30-day cooldown after Skip, opt-in via `knowledge-base/project/promotion-config.yml` + append-only `knowledge-base/project/learnings/promotion-log.md` | CPO+CTO+CLO consensus. Without all four, the user-brand-critical guarantee evaporates (rubber-stamp, PR-storm, whack-a-mole, no consent, no audit trail). |
| 7 | **Default:** OFF | Operator must commit `promotion-config.yml` with `enabled: true` to activate. Capability consent (per CLO) is separate from per-PR consent. |
| 8 | **Tier classification:** automated via the existing `cq-agents-md-tier-gate` logic that compound's Route-Learning-to-Definition step already encodes | The placement gate must apply to promoted rules, not just hand-edited ones. |
| 9 | **Reconciliation:** close #421 as superseded by #2720 (this brainstorm) | Single tracking issue, single design conversation. The hooks-only narrowing in #421 is preserved in v2 scope. |
| 10 | **GDPR-gate:** mandatory at plan Phase 2.7 and work Phase 2 exit | The loop reads from operator-session-derived learnings and writes to artifacts that propagate to other operators via plugin update — Chapter V / Art. 28 surface per CLO. |

## Non-Goals (v1)

- Hook proposals (defer to v2 with explicit revert path via `scripts/retired-rule-ids.txt`).
- Inline /compound runtime surface (defer to v2 if cron-only proves insufficient).
- Per-category threshold override (default global N=5 is sufficient until empirical data justifies tuning).
- Auto-merge of promotion PRs (manual-confirm via PR review is non-negotiable).
- Demotion path for under-firing rules (already handled by `scripts/rule-prune.sh --propose-retirement`; do not duplicate).
- Frontmatter mutation on learning files (preserves ADR-1 from compound Phase 1.5 design).

## User-Brand Impact

| Field | Value |
|-------|-------|
| **Threshold** | `single-user incident` |
| **Artifact at risk** | `AGENTS.md`, `plugins/soleur/skills/**/SKILL.md`, `.claude/hooks/**` (v2) |
| **Vector** | A misfired or low-quality auto-promoted rule lands via merged PR; cascades to every operator's session via `@AGENTS.md` import or skill invocation; subtle behavior degradation until manual rollback. |
| **Worst-case experiences (operator)** | (a) Cascading agent-behavior degradation: bad promoted rule silently misroutes work in every session. (b) Token-cost explosion: AGENTS.md crosses 37k/40k thresholds, every operator pays 10–22% per-turn token overhead until manual cleanup (cited from ETH Zurich, learning `2026-04-18-agents-md-byte-budget-and-why-compression.md`). (c) False sense of safety: operators trust auto-promoted rules more than human-edited ones; real workflow gaps stay un-codified because nobody reviews compound output anymore. |
| **Mitigations carried into spec** | All four guardrails (byte-cap suppression, per-week cap, cooldown, opt-in + audit log). Tier-gate automation. Provenance trailer. Default OFF. CLO non-repudiation log. GDPR-gate at plan Phase 2.7. user-impact-reviewer at PR review per `hr-weigh-every-decision-against-target-user-impact`. |

## Open Questions

- **Cluster identity stability across runs.** If LLM clustering produces slightly different groupings week-over-week, how does the cooldown-after-Skip mechanism identify "this is the same cluster as last week's rejected proposal"? Proposed: hash a canonical sorted list of source-learning paths as the cluster ID; if any source learning is added/removed, treat as a new cluster (low cost: re-trigger cooldown logic).
- **AGENTS.md tier-gate automation accuracy.** The classification (already-enforced / domain-scoped / cross-cutting) is judgment-call today when humans do it. Can an LLM classify reliably enough that we trust the routing? Mitigation: tier classification is logged in the PR body; reviewer can override before merge.
- **Plugin-scope vs consumer-local scope** (CLO finding #4). For v1, restrict promotion targets to the consumer's local `knowledge-base/` and `plugins/soleur/**` paths owned by this repo. Defer cross-plugin propagation (where a Soleur-plugin update would push promoted rules to downstream operators) to v2 with an explicit `--scope=plugin` flag and ToS update.
- **Bootstrap cost.** First run on the existing ~280-file learnings corpus may cluster many proposals at once. Per-week cap of 2 means it takes ~weeks to drain backlog. Acceptable; flag in plan for empirical tuning.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations (skipped — no vendor/expense), Product, Legal, Sales (skipped), Finance (skipped), Support (skipped).

### Product (CPO)

**Summary:** Infrastructure largely exists (Phase 1.5 Deviation Analyst, `rule-metrics.json`, Route-to-Definition placement gate). Promotion loop is a counter+threshold+proposer layer on top, not a green-field build. Highest risk is promotion-fatigue (operator dismisses every diff blindly) — mitigated by per-week cap + cooldown + opt-in.

### Engineering (CTO)

**Summary:** SMALL complexity (1-2 days). Telemetry pipeline (`incidents.sh` → `rule-metrics-aggregate.sh` → `rule-metrics.json`) is in place; the missing piece is a **learning-recurrence counter** keyed by cluster (not a rule_id counter, which is what `rule-metrics.json` provides today). Bad-rule kill switch via `scripts/retired-rule-ids.txt` exists. Two ADR-worthy decisions: (a) cluster-keyed counter store (parallel JSON file, not frontmatter), (b) interactive-confirm in all modes including headless.

### Marketing (CMO)

**Summary:** Launch-blog-post-worthy. External name "Learning Ratchet" or "Compounding Gate" (keep "promotion loop" as internal/code term). Bundle launch with #2719 (skill-security-scan) as the "self-improvement with safety rails" narrative. Risk if undermarketed: first surprise PR reads as the agent "going off-script"; mitigation = changelog disclosure + provenance comment near promoted rules. Risk if oversold: "self-improving AI" triggers AGI-adjacent expectations; lead with the human gate, not the autonomy.

### Legal (CLO)

**Summary:** USER_BRAND_CRITICAL surface. Four required mitigations: (1) tamper-evident audit log (`promotion-log.md` append-only) + commit trailer for non-repudiation; (2) two-tier consent (capability opt-in via config + per-PR confirm); (3) pre-promotion `gdpr-gate` scan over source learnings to prevent PII propagation through the loop; (4) for v2 plugin-scope promotions, ToS/Privacy Policy update + auto-CHANGELOG entry. v1 stays consumer-local to defer (4).

## Capability Gaps

None. The required infrastructure exists across compound, compound-capture, gdpr-gate, rule-metrics, and the existing weekly-cron pattern in `.github/workflows/rule-metrics-aggregate.yml`. Evidence:

- `find . -path '*/scripts/rule-metrics-aggregate*' -type f` → `scripts/rule-metrics-aggregate.sh` exists.
- `find . -path '*/.github/workflows/rule-metrics-aggregate*'` → workflow exists, runs Sunday 00:00 UTC.
- `find . -path '*/scripts/retired-rule-ids.txt'` → exists; pointer-preservation pattern documented.
- `find . -path '*/plugins/soleur/skills/gdpr-gate*'` → skill exists for the pre-promotion scan requirement.
- `git ls-files plugins/soleur/skills/compound-capture/schema.yaml` → schema exists for any future per-cluster metadata extension.

## References

- Parent: #2718 (claude-skills audit action plan)
- Superseded: #421 (deferred Layer 2 weekly CI sweep)
- Layer 1 (shipped): #397 / PR #416
- Prior brainstorm: `knowledge-base/project/brainstorms/2026-03-03-self-healing-workflow-brainstorm.md`
- AGENTS.md rules: `cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`, `cq-rule-ids-are-immutable`, `wg-every-session-error-must-produce-either`, `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`
- Compound infrastructure: `plugins/soleur/skills/compound/SKILL.md` (Phase 1.5, Phase 1.6, Route-to-Definition), `plugins/soleur/skills/compound-capture/SKILL.md` (Step 8), `plugins/soleur/skills/compound-capture/schema.yaml` (ADR-1 line 116-119)
- Telemetry: `.claude/hooks/lib/incidents.sh`, `scripts/rule-metrics-aggregate.sh`, `knowledge-base/project/rule-metrics.json`
- Demotion sibling: `scripts/rule-prune.sh` (do not duplicate; promotion is its inverse)
