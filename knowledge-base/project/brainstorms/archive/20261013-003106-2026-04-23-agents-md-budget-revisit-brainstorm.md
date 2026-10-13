---
title: AGENTS.md budget revisit — ship-shrink with discoverability litmus + retired-ids allowlist
date: 2026-04-23
related: [2327, 2686, 2762, 2720, 2581, 2754]
branch: feat-agents-md-shrink
status: decided
---

# AGENTS.md budget revisit — ship-shrink with discoverability litmus

## Context

Claude Code now emits a harness-level performance warning: `⚠ Large AGENTS.md will impact performance (40.5k chars > 40.0k)`. This supersedes the internal 115-rule / 40,000-byte threshold set in PR #2754 (merged 2026-04-21, issue #2686). The raise shipped two days ago and is already 98% consumed (113/115 rules, 40,654 bytes).

**Fresh audit (2026-04-23):**

| File | Rules | Bytes | Always-loaded? |
|---|---|---|---|
| `AGENTS.md` | 113 | 40,654 | **Yes** (via `CLAUDE.md @AGENTS.md`) |
| `knowledge-base/project/constitution.md` | 238 | 53,064 | No (read on-demand) |

Earlier framing of "93k combined always-loaded" was wrong. Only `AGENTS.md` pays the every-turn cost. Constitution.md is cold-path and out of scope for this brainstorm.

**AGENTS.md section distribution:** Code Quality 49 (43%), Hard Rules 28, Workflow Gates 25, Review & Feedback 6, Communication 3, Passive Domain Routing 2.

**Empirical findings from repo + learnings research:**

1. **PR #2754 pointer-migration measured +21 bytes net.** The "pointer lines" pattern (short tombstone + preserved `[id:]` tag in AGENTS.md, full body moved to skill/hook file) saved ~0 bytes because pointer lines still cost ~200 bytes each. Rule count stayed flat. The prior shrink strategy was structurally byte-neutral.

2. **Rule-prune pipeline is telemetrically dead.** `scripts/rule-metrics-aggregate.sh` runs on cron (4 runs since 2026-04-15) but all 113 rules show `hit_count=0, first_seen=null`. Only 3 of 7 hooks call `emit_incident`. Skill-enforced rules have no self-report path. `scripts/rule-prune.sh --dry-run` would file 101 false-positive retirement issues.

3. **Growth rate is the primary problem: 4.7 rules/day.** The +15-rule raise from PR #2754 was consumed in 2 days. `wg-every-session-error-must-produce-either` mandates rule creation on every session error with no learning-only exit criterion — this is the fire hose.

4. **Deletion is blocked by `scripts/lint-rule-ids.py`.** Immutability enforcer rejects removal of any `[id:]` line. Issue #2762 tracks the unblock (retired-ids allowlist at `scripts/retired-rule-ids.txt`). Until #2762 lands, shrink is capped at byte-neutral pointer-migration.

5. **Repo precedent for a discoverability litmus.** `knowledge-base/project/learnings/2026-02-25-lean-agents-md-gotchas-only.md` documents a 127→26 line cleanup using the test: *"Can the agent discover this on its own by reading the code, running the command, or trying it?"* If yes, delete. This precedent is not being applied to the 113 current rules.

6. **Context-file cost is real, not just the warn threshold.** Same 2026-02-25 learning cites ETH Zurich research: always-loaded context files add 10-22% reasoning tokens and 15-20% cost per turn. The 40k warn is Claude Code's proxy for this underlying cost.

## What We're Building

A single PR under **Approach D** that does four things:

1. **Land #2762: retired-ids allowlist.** Amend `scripts/lint-rule-ids.py` to accept `scripts/retired-rule-ids.txt` as an allowlist of IDs that may be absent from AGENTS.md. Each entry includes the ID, retirement date, and a breadcrumb (learning file path or replacement rule ID). This unblocks rule deletion without re-opening the rule-ID-reuse hazard.

2. **Amend `wg-every-session-error-must-produce-either`** with a discoverability-litmus exit criterion: *"If the error class is discoverable by an agent reading the code, running the command, or trying it once (i.e., the fix surfaces with a clear error message or visible diff), a learning-file entry is sufficient and NO AGENTS.md rule should be created. Only create an AGENTS.md rule when the constraint is hidden (tool quirk not in docs, silent-failure mode, surprising invariant that only surfaces post-merge, or blast-radius incident requiring force-push recovery)."* Compound step 8 will apply the litmus during rule-promotion review.

3. **Execute a delete pass** applying the litmus to all 113 existing rules. Each deletion records: rule ID retired → `scripts/retired-rule-ids.txt`, one-line justification in the PR description, and (if the learning is still valuable) a breadcrumb pointer from the retired ID to a learning file. Pointer-migration (PR #2754 pattern) is abandoned for rules where the skill/hook is ALWAYS invoked — those get full deletion; conditional skill/hook firings keep a minimal pointer.

4. **Target AGENTS.md ≤ 32,000 bytes** (80% of 40k warn). From current 40,654, this requires ~8.6k bytes of net reduction — roughly 25 full-deletion rules at mean 357 bytes/rule. The target is expressed in **bytes only**; rule count is a secondary metric.

**Out of scope (tracked separately):**

- **Telemetry fix** (wire remaining hooks + skill-invocation self-report) — deferred to a new issue. Rationale: telemetry helps evaluate FUTURE rules; the current shrink is judgment-driven via the litmus, and telemetry for existing rules would show hit_count=0 regardless (aggregator only since 2026-04-15, most rules newer than that).
- **Constitution.md size** — cold-path, not always-loaded, outside the harness-warn trigger.
- **Compound skill SKILL.md edits** — litmus logic lives in the amended rule text; compound step 8 already references the rule. If step 8 needs new wording, do it in the same PR.

## Why This Approach

- **Approach D vs Approach B (two bundled PRs) vs Approach A (three sequential PRs):** D ships the immediate shrink fastest because telemetry is non-blocking for THIS shrink (all existing rules would show hit_count=0 regardless of telemetry quality). B and A spread the work across 2-3 review cycles without affecting the final byte target.
- **Discoverability litmus vs recurrence threshold:** Recurrence-based promotion (rule only on 2nd occurrence) requires telemetry to track recurrence — not available. Discoverability is the existing repo precedent (2026-02-25 cleanup) and can be applied with prose-only judgment.
- **Bytes-only target vs rule count:** Claude Code warns on bytes. The Harness cost (ETH Zurich: 10-22% reasoning tokens) scales with bytes, not rule count. Rule count is a human-readable proxy, not the load-bearing metric.
- **<32k vs <28k vs <36k:** 32k = 80% of warn, ~8k headroom ≈ 4-5 days of buffer at current 1.8 KB/day growth rate. With the amended inflow rule reducing inflow, expected buffer extends to 2-4 weeks. 28k (70%) requires deleting rules that are genuinely contested; 36k (90%) refills in ~3 weeks with no inflow change.
- **Pointer-migration abandoned:** empirical measurement showed it saves ~0 bytes. Full deletion via `retired-rule-ids.txt` is the only byte-positive path.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Target metric | Bytes, not rule count | Claude Code warns on bytes; research shows cost scales with bytes |
| Target ceiling | ≤ 32,000 bytes AGENTS.md (80% of 40k warn) | ~8k headroom ≈ 4-5 days buffer at current growth; longer with amended inflow rule |
| Scope | AGENTS.md only | Constitution is on-demand, not always-loaded |
| Sequencing | Approach D — single PR, telemetry deferred | Telemetry is non-blocking for this shrink (all rules would show 0 hits anyway) |
| Deletion unblock | Land #2762 in same PR | Retired-ids allowlist is the load-bearing enabler for real byte savings |
| Inflow rule | Discoverability litmus added to `wg-every-session-error-must-produce-either` | Repo precedent (2026-02-25); can be applied without telemetry |
| Migration pattern | Full deletion (via retired-rule-ids.txt) for always-invoked skill/hook rules; minimal pointer for conditionals | Pointer-migration measured +21 bytes net in PR #2754 — abandon byte-neutrally |
| Pointer-migration legacy | Existing pointer lines from PR #2754 stay; re-evaluate per-rule during delete pass | Avoid churn on already-migrated rules unless litmus flags them |
| Rule-ID immutability | Preserved via `scripts/retired-rule-ids.txt` — retired IDs never reused | Per `cq-rule-ids-are-immutable`; deletion is allowed only with allowlist entry |
| Learning-file breadcrumbs | For deleted rules whose learning is still valuable, add 1-line pointer from `retired-rule-ids.txt` entry to the learning file | Preserves institutional memory without always-loaded cost |

## Implementation Notes

1. **Order of operations inside the PR:**
   - (a) Amend `scripts/lint-rule-ids.py` + create `scripts/retired-rule-ids.txt` (empty, with header).
   - (b) Edit `wg-every-session-error-must-produce-either` text (adds ~150 bytes).
   - (c) Apply delete pass: for each rule, apply litmus → if fail, append ID + date + breadcrumb to `retired-rule-ids.txt`, delete the `- ...` line from AGENTS.md.
   - (d) Update `cq-agents-md-why-single-line` to reflect new target (bytes-only, 32k warn / 40k hard fail).
   - (e) Update compound SKILL.md step 8 byte threshold if it still references 40k / 115.
   - (f) Verify: `bash scripts/lint-rule-ids.py` passes, `wc -c AGENTS.md` < 32,000, commit.

2. **Litmus application procedure (per rule, in order):**
   - (i) Read the rule text + its `**Why:**` annotation.
   - (ii) Ask: "Would an agent hit this constraint with a clear error, a visible diff, or a command failure?" If yes → fail litmus → delete.
   - (iii) If no, ask: "Is this a hidden constraint, silent-failure mode, or blast-radius incident?" If yes → pass litmus → keep.
   - (iv) If ambiguous, err on KEEP — litmus should be tight, not aggressive.
   - (v) Document the per-rule decision in the PR description so reviewers can challenge individual calls.

3. **Expected deletion candidates (preliminary, validated during planning phase):**
   - Rules citing one-time incidents with strong error signals (e.g., `cq-gh-issue-create-milestone-takes-title` — `gh` emits a clear error; agent can discover).
   - Rules that are documentation of visible patterns (e.g., `cq-doppler-service-tokens-are-per-config` — silent failure, LIKELY KEEP).
   - Rules with broken or misleading hook references where enforcement is real but the tag format is stale — these stay but get normalized, not deleted.

4. **Pre-merge verification:**
   - `wc -c AGENTS.md` < 32,000
   - `bash scripts/lint-rule-ids.py` exits 0
   - `grep -c '^- ' AGENTS.md` (informational only)
   - Manual spot-check: retired rules still have a path to re-learn the constraint (via linked learning file or skill/hook header).

## Non-Goals

- Fixing the telemetry pipeline (`emit_incident` coverage gaps, skill-invocation self-report) — tracked separately.
- Migrating constitution.md rules or changing its threshold.
- Changing the per-rule byte cap (600) — all 113 current rules are under it.
- Re-doing the `**Why:**` compression pass from PR #2544.
- Adding new hooks or new skill gates in this PR.
- Introducing a per-section byte cap — the global byte target is sufficient.
- Rewriting `knowledge-base/project/learnings/` — this PR may ADD breadcrumb references from `retired-rule-ids.txt` but does not restructure existing learnings.

## Open Questions

- **How many rules actually fail the litmus?** Resolution: the planning skill produces the candidate list during `/soleur:plan`. If fewer than 25 rules fail, target becomes advisory and we accept a smaller shrink or widen the litmus (but prefer KEEP bias to avoid deletion of load-bearing rules).
- **Do existing PR #2754 pointer-migrated rules get deleted?** Resolution: they pass through the same litmus. If the skill/hook is ALWAYS invoked in the relevant workflow (e.g., `browser-cleanup-hook.sh` fires on every Playwright close), the pointer can be deleted. If conditional, keep.
- **Should `cq-rule-ids-are-immutable` itself be reworded to reflect the allowlist?** Yes — add one sentence noting that removal is permitted via `scripts/retired-rule-ids.txt`. Done in same PR.

## Domain Assessments

**Assessed:** Engineering (CTO-adjacent — tooling governance, internal to agent harness).

Engineering-only decision. No marketing, legal, operations, product, sales, finance, or support implications. No user-facing change. No new infrastructure. The amendment affects how agents (Claude + developers) capture lessons from session errors — a process/tooling knob.

Prior brainstorm (2026-04-21) reached the same domain-scoping conclusion. Revisiting the scope would add ceremony without new signal. CTO function is served by the repo-research-analyst findings (context-cost data, pipeline state). CPO function is not engaged because "rule as product" is an agent-internal API, not a user-facing product surface.

## References

- **Tool signal:** Claude Code warning `Large AGENTS.md will impact performance (40.5k chars > 40.0k)`
- **Prior brainstorm:** `knowledge-base/project/brainstorms/2026-04-21-agents-md-rule-threshold-brainstorm.md`
- **Prior PR:** #2754 (MERGED 2026-04-21) — raised threshold 100→115, measured +21 bytes net on pointer migration
- **Load-bearing unblock:** #2762 (OPEN) — `lint-rule-ids.py` retired-ids allowlist
- **Related open issues:** #2327 (stale rule audit), #2581 (markdown-rule narrow scope), #2720 (compound promotion loop)
- **Foundational learning:** `knowledge-base/project/learnings/2026-02-25-lean-agents-md-gotchas-only.md` (ETH Zurich context cost + discoverability litmus)
- **Recent learnings:**
  - `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` (immutability constraint + allowlist unblock)
  - `2026-04-18-agents-md-byte-budget-and-why-compression.md` (bytes is the right metric)
  - `2026-04-07-rule-budget-false-alarm-fix.md` (only @-included files are always-loaded)
  - `2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md` (aggregator infra)
- **Threshold rule under amendment:** `cq-agents-md-why-single-line`, `wg-every-session-error-must-produce-either`
- **Immutability enforcer:** `scripts/lint-rule-ids.py` (to be amended)
- **Telemetry pipeline (deferred work):** `.claude/hooks/lib/incidents.sh`, `scripts/rule-metrics-aggregate.sh`, `scripts/rule-prune.sh`
