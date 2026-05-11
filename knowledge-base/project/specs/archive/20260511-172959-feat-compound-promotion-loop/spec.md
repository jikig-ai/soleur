# Feature: Compound Promotion Loop (self-healing CI sweep)

**Issue:** #2720
**Parent:** #2718 (claude-skills audit action plan)
**Supersedes:** #421 (deferred Layer 2 weekly CI sweep)
**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-11-compound-promotion-loop-brainstorm.md`
**Branch:** `feat-compound-promotion-loop`
**PR:** #3559
**Status:** specced
**Brand-survival threshold:** `single-user incident`

## Problem Statement

`AGENTS.md` `wg-every-session-error-must-produce-either` requires every session error to produce a rule, skill edit, hook, or learning-file entry. Today the rule relies on human vigilance during `/compound`. When the same root cause produces multiple learnings across sessions without being noticed-and-codified, the workflow gap stays open and the same incident recurs.

The 2026-03-03 self-healing-workflow brainstorm specified a two-layer remedy: Layer 1 (Deviation Analyst, in-session) shipped via PR #416. Layer 2 (weekly CI sweep, cross-session) was deferred as #421. This spec realizes Layer 2 under the #2720 framing from the 2026-05 claude-skills audit.

## Goals

1. Detect recurring root causes in the `knowledge-base/project/learnings/` corpus by LLM-clustering, threshold N=5.
2. Open one draft PR per qualifying cluster, applying a proposed skill-instruction edit or AGENTS.md rule addition with a provenance trailer.
3. Default OFF; require operator opt-in via `knowledge-base/project/promotion-config.yml`.
4. Never auto-merge — operator review/merge via normal GitHub PR flow is the load-bearing consent gate.
5. Preserve the existing demotion path (`scripts/rule-prune.sh`); promotion loop is its inverse, never its replacement.
6. Carry forward `single-user incident` brand-survival threshold from brainstorm into plan, work, ship, and review-time gates.

## Non-Goals

1. **Hook proposals.** Defer to v2 due to highest blast-radius (PreToolUse hooks can wedge sessions).
2. **Inline /compound runtime surface.** Defer to v2 if cron-only proves insufficient. The Layer 1 Deviation Analyst already surfaces in-session.
3. **Per-category threshold override.** Default global N=5; defer per-category tuning until empirical data justifies.
4. **Auto-merge of promotion PRs.** Manual-confirm via PR review is non-negotiable.
5. **Demotion path.** Already handled by `scripts/rule-prune.sh --propose-retirement`.
6. **Frontmatter mutation on learning files.** Preserves ADR-1 from compound Phase 1.5 design (`compound/SKILL.md` line 162).
7. **Plugin-scope promotions.** v1 restricts targets to consumer-local `knowledge-base/` and `plugins/soleur/**` paths owned by this repo. Cross-plugin propagation deferred to v2 with explicit `--scope=plugin` flag and ToS update.
8. **Embedding-based dedup.** LLM clustering at cron time is sufficient for v1; defer vector embeddings to v2 if needed.

## Functional Requirements

### FR1: Weekly cron sweep

A new GitHub Actions workflow runs Sunday 00:00 UTC (aligned with `rule-metrics-aggregate.yml`). On each run, the workflow:

1. Reads `knowledge-base/project/promotion-config.yml`. Exits no-op if `enabled: true` is missing or absent.
2. Loads the full `knowledge-base/project/learnings/` corpus (recurses subdirectories).
3. Invokes an LLM clustering step that groups learnings by problem/root-cause semantic similarity.
4. For each cluster of size ≥ 5, proceeds to FR2.

### FR2: Tier-gated proposal classification

For each qualifying cluster:

1. Read the cluster's representative root cause.
2. Apply `cq-agents-md-tier-gate` classification:
   - **Already-enforced** (hook/skill/scanner present) → skip with log entry "already enforced by `<artifact>`."
   - **Domain-scoped** (single skill/agent/test boundary) → propose a skill-instruction edit to the owning SKILL.md.
   - **Cross-cutting session invariant** → propose an AGENTS.md rule addition.
3. Log the chosen tier + rationale in the PR body for reviewer override.

### FR3: Draft PR with provenance trailer

For each tier-gated proposal, the cron:

1. Creates a feature branch `self-healing/auto-<cluster-hash>`.
2. Applies the proposed diff (skill bullet append, or AGENTS.md rule addition with `[id: <kebab-id>]` tag).
3. Commits with structured trailer:
   ```
   Promoted-By: <git-user.email reading promotion-config.yml owner>
   Proposed-By: compound-promotion-loop v<workflow-sha>
   Source-Learnings: <path1>,<path2>,...,<pathN>
   Threshold-Hit: 5/5
   Cluster-Hash: <sha256 of sorted source-learning paths>
   ```
4. Opens a draft PR labeled `self-healing/auto`, body includes: cluster summary, tier classification + rationale, source-learning links, byte-impact preview (`wc -c AGENTS.md` before/after if AGENTS.md target).

### FR4: AGENTS.md byte-cap suppression

Before proposing an AGENTS.md placement, the cron:

1. Reads current `wc -c AGENTS.md`.
2. If > 37000 bytes, refuses AGENTS.md placement.
3. Re-routes to skill placement if a domain-scoped target exists.
4. If no skill target exists and AGENTS.md is over budget, skips this cluster and logs "deferred — AGENTS.md over byte cap, no skill target."

### FR5: Per-week PR cap

The cron tracks PRs opened with the `self-healing/auto` label in the current ISO week:

1. Hard cap: max 2 open PRs per week.
2. If cap reached, queue remaining proposals as JSON entries in `.github/promotion-queue.json` for the next week's run.
3. Cap counts only PRs opened by THIS workflow; human-opened PRs with the same label do not consume budget.

### FR6: 30-day cooldown after Skip

When a `self-healing/auto` PR is closed without merging:

1. The cron records the PR's `Cluster-Hash` trailer + close date in `.github/promotion-cooldowns.json`.
2. On subsequent runs, any cluster whose hash is in the cooldown ledger and whose entry is younger than 30 days is skipped.
3. After 30 days, the entry is purged; the cluster becomes eligible again.
4. If the cluster's source-learning set changes (any addition/removal), the new `Cluster-Hash` differs and is NOT in cooldown — treated as a new cluster.

### FR7: Opt-in capability gate + audit log

1. **Opt-in:** `knowledge-base/project/promotion-config.yml` MUST exist and contain `enabled: true` for the cron to take any action. Default repo state is OFF.
2. **Audit log:** Every proposal (regardless of operator decision) appends a row to `knowledge-base/project/learnings/promotion-log.md` (append-only, dated). Schema: `<date> | <cluster-hash> | <target-path> | <source-learning-count> | <pr-number> | <tier> | <decision-pending|merged|closed>`.
3. The cron updates the `<decision>` column post-merge or post-close in the same log via a follow-up commit on a separate housekeeping branch.

### FR8: Pre-promotion GDPR scan

Before opening any draft PR, the cron invokes `/soleur:gdpr-gate` over the N source learnings:

1. If any source learning fails GDPR redaction (PII patterns per the gdpr-gate skill's canonical regex), the proposal is REFUSED, the cluster is added to a `gdpr-blocked` ledger, and a GitHub issue is filed against the offending learning(s) for redaction.
2. Promotion does not retry until the offending learnings pass redaction.

### FR9: Issue close on supersede

When this spec is shipped, also close #421 with the comment: "Superseded by #2720 / PR #3559. v1 ships skill + AGENTS.md targets; hooks deferred to v2."

## Technical Requirements

### TR1: Workflow integration

- New file: `.github/workflows/compound-promotion-loop.yml`. Schedule: `0 0 * * 0` (matches `rule-metrics-aggregate.yml`). Permissions: `contents: write`, `pull-requests: write`, `issues: write`.
- Use `secrets.SOLEUR_GH_TOKEN` not `GITHUB_TOKEN` to avoid the bot-PR CI cascade per `2026-03-03 self-healing-workflow brainstorm` (constitution.md line 102).
- Workflow concurrency group: `compound-promotion-loop-${{ github.ref }}` to prevent overlapping runs.

### TR2: LLM clustering implementation

- Use `claude-code-action` (already used by other workflows under `.github/workflows/`).
- Prompt the action with the full learnings corpus + the existing tier-gate text from `compound/SKILL.md` Route-Learning-to-Definition step.
- Output JSON: `[{cluster_id, root_cause_summary, tier, target_path, source_learnings: [...], proposed_diff}, ...]`.
- Cluster minimum size = 5; the action returns only qualifying clusters.

### TR3: Persistent state

Three new repo-tracked files (NOT gitignored, so cross-clone state is preserved):

- `knowledge-base/project/promotion-config.yml` — operator-committed; presence + `enabled: true` required.
- `.github/promotion-queue.json` — cron-managed overflow queue (FR5).
- `.github/promotion-cooldowns.json` — cron-managed cooldown ledger (FR6).
- `knowledge-base/project/learnings/promotion-log.md` — append-only audit log (FR7).

### TR4: Tier classification accuracy

The LLM tier classification (FR2) must be reviewable. The PR body MUST include:

1. Tier chosen (already-enforced / domain-scoped / cross-cutting).
2. One-sentence rationale.
3. Alternative tier(s) considered.

This makes the reviewer's override decision a single-step amend rather than a full re-classification.

### TR5: Atomicity

- Each promotion (one PR) MUST be atomic: either all of (branch, commit, PR open, queue/cooldown ledger update, audit log append) succeed, or all are rolled back.
- The workflow uses `set -euo pipefail` and a cleanup trap that deletes the local branch + closes the in-progress PR if any post-PR-open step fails.

### TR6: Bootstrap behavior

The first cron run on the existing ~280-file learnings corpus may identify many qualifying clusters at once. Per FR5, only 2 PRs land in the first week; remaining clusters queue. This is the intended bootstrap behavior; flag in `/ship` for empirical tuning of the per-week cap after 4 weeks of operation.

### TR7: Kill switch

To halt the loop entirely (not just one cluster), the operator sets `enabled: false` in `promotion-config.yml`. The next cron run reads the config and exits no-op. No new PRs open until the flag flips back. Existing open `self-healing/auto` PRs are unaffected (operator handles via normal close).

### TR8: Cluster-hash stability

The `Cluster-Hash` (FR3, FR6) is `sha256(sorted(source_learning_paths))`. Sorted to make the hash order-independent. Path-based (not content-based) so minor edits to a learning file don't break cluster identity. If a source learning is renamed, the cluster hash changes → treated as a new cluster (acceptable; rename is a rare event).

### TR9: GDPR-gate carry-forward

Per `hr-gdpr-gate-on-regulated-data-surfaces`, the plan MUST invoke `/soleur:gdpr-gate` at Phase 2.7. The work skill MUST invoke at Phase 2 exit. The ship skill's Phase 5.5 conditional gate MUST verify the workflow YAML doesn't hand the cron unrestricted access to PII-bearing learnings.

### TR10: User-impact-reviewer at PR review

Per `hr-weigh-every-decision-against-target-user-impact`, the brand-survival threshold `single-user incident` requires the `user-impact-reviewer` agent to review the implementing PR (#3559's eventual non-draft state). This is non-optional; CI blocks merge until the reviewer approves.

## Acceptance Criteria

- [ ] AC1: Workflow file exists, runs Sunday 00:00 UTC, exits no-op when `promotion-config.yml` missing or `enabled: false`.
- [ ] AC2: With `enabled: true` and a synthetic learnings corpus of 5+ similar files, the cron opens one draft PR with the provenance trailer + tier classification.
- [ ] AC3: Repeated runs do NOT duplicate proposals — same cluster hash is detected via cooldown ledger or open-PR check.
- [ ] AC4: Per-week cap of 2 PRs is enforced; overflow clusters land in `.github/promotion-queue.json`.
- [ ] AC5: Closing a `self-healing/auto` PR without merging adds an entry to `.github/promotion-cooldowns.json`; subsequent runs within 30 days skip the cluster.
- [ ] AC6: AGENTS.md byte-cap suppression triggers when `wc -c AGENTS.md > 37000`; cluster routes to skill or skips.
- [ ] AC7: A learning file containing a synthetic email address fails the gdpr-gate scan; the cron refuses to promote and files a redaction issue.
- [ ] AC8: `promotion-log.md` appends one row per proposal; row updates from `pending` to `merged|closed` after operator action.
- [ ] AC9: Issue #421 is closed with the supersede comment as part of the shipping PR's merge.
- [ ] AC10: User-impact-reviewer agent run on the implementing PR returns approval before merge.

## Open Questions (for plan)

- LLM clustering prompt design: how to keep cluster boundaries stable week-over-week without an embedding store? (TR8 mitigates via path-hash, but the LLM may still produce different cluster boundaries on different runs.)
- Tier classification confidence: should the cron require the LLM to emit a confidence score and refuse low-confidence classifications? (Default for v1: trust the LLM, gate via PR review.)
- Bootstrap-week batching: should the first run intentionally cap at 1 PR (not 2) to give the operator time to evaluate before the loop accelerates?
