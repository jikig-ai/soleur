# Feature: AGENTS.md budget revisit — shrink to ≤ 32,000 bytes

## Problem Statement

Claude Code now emits a harness-level performance warning: `⚠ Large AGENTS.md will impact performance (40.5k chars > 40.0k)`. `AGENTS.md` is the sole always-loaded governance file (via `CLAUDE.md @AGENTS.md`), currently 113 rules / 40,654 bytes. Context-file cost research (ETH Zurich, cited in `2026-02-25-lean-agents-md-gotchas-only.md`) shows always-loaded files add 10-22% reasoning tokens and 15-20% cost per turn. The tool warning is a proxy for this underlying cost.

Three structural problems prevent a durable fix:

1. **Growth rate is 4.7 rules/day** — the prior 100→115 rule-count raise (PR #2754, merged 2026-04-21) was consumed in 2 days. The `wg-every-session-error-must-produce-either` rule mandates rule creation on every session error with no learning-only exit criterion.
2. **Pointer-migration saves zero bytes** — PR #2754's pattern measured +21 bytes net. Pointer lines cost ~200 bytes each; moving rule prose to skill/hook files leaves the pointer behind.
3. **Rule deletion is blocked by `scripts/lint-rule-ids.py`** — immutability enforcer rejects removal of any `[id:]` line. Issue #2762 tracks the unblock but hasn't landed.

Secondary issue: the rule-metrics telemetry pipeline runs on cron but all rules show `hit_count=0, first_seen=null` because only 3 of 7 hooks emit incidents. This blocks the automated `rule-prune.sh` surface but does NOT block the current shrink (existing rules are judged by litmus, not telemetry).

## Goals

- Reduce `AGENTS.md` to ≤ 32,000 bytes (80% of 40k warn; ~8k headroom).
- Land the retired-ids allowlist (#2762) so rule deletion is no longer mechanically blocked.
- Amend `wg-every-session-error-must-produce-either` with a discoverability-litmus exit criterion so future inflow drops.
- Preserve institutional memory: every deleted rule's learning must remain accessible (either via the originating learning file, or via a breadcrumb from `scripts/retired-rule-ids.txt`).
- Ship in a single reviewable PR (Approach D).

## Non-Goals

- **Fixing the rule-metrics telemetry pipeline** (broken `emit_incident` coverage, skill-invocation self-report). Tracked in a separate new issue. Rationale: telemetry helps evaluate FUTURE rules; existing rules would show `hit_count=0` regardless.
- **Shrinking `knowledge-base/project/constitution.md`** — cold-path (on-demand), outside the tool's warn threshold.
- **Changing the per-rule byte cap** (600) — all 113 current rules are under it.
- **Re-running the `**Why:**` compression pass** (PR #2544 already did this).
- **Adding new hooks or new skill gates** in this PR.
- **Introducing per-section byte caps** — the global byte target is sufficient.
- **Rewriting existing learnings** — may ADD breadcrumb references but does not restructure.
- **Blanket pointer-migration legacy cleanup** — existing PR #2754 pointer lines stay unless they fail the litmus during the delete pass.

## Functional Requirements

### FR1: Retired-ids allowlist (closes #2762)

`scripts/lint-rule-ids.py` accepts a new file `scripts/retired-rule-ids.txt` as an allowlist. Each entry on its own line:

```text
<rule-id> | <retirement-date YYYY-MM-DD> | <PR-number> | <breadcrumb: learning-file-path or replacement-rule-id>
```

Lines starting with `#` are comments. Blank lines are ignored. The linter:

- Does NOT fail when a known `[id:]` is absent from `AGENTS.md` IF the ID is present in `retired-rule-ids.txt`.
- DOES fail if a `[id:]` is absent from both `AGENTS.md` AND `retired-rule-ids.txt` (preserves immutability).
- DOES fail if the same ID appears in both (rule cannot be simultaneously active and retired).
- DOES fail if a `retired-rule-ids.txt` entry is malformed (missing required fields, invalid date).

### FR2: Inflow rule amendment (discoverability litmus)

`wg-every-session-error-must-produce-either` gains an exit criterion:

> **Exit criterion (discoverability litmus):** If the error class is discoverable by an agent reading the code, running the command, or trying it once — i.e., the fix surfaces with a clear error message, a visible diff, or a command failure — a learning-file entry alone is sufficient and NO AGENTS.md rule should be created. Only create an AGENTS.md rule when the constraint is hidden (tool quirk not in docs, silent-failure mode, surprising invariant surfacing only post-merge, or blast-radius incident requiring force-push recovery).

`compound` skill step 8 gains an explicit check: before adding a rule to AGENTS.md, the skill documents the litmus decision in the PR description, including why the rule class fails the litmus (i.e., why the agent CANNOT discover the constraint on its own).

### FR3: Delete pass via litmus

Each of the 113 existing rules is evaluated against the litmus. For each rule that fails (i.e., IS discoverable by the agent):

- The `[id:]` is added to `scripts/retired-rule-ids.txt` with retirement date, this PR number, and breadcrumb.
- The `- ...` line is deleted from `AGENTS.md`.
- If the rule's learning is still valuable (institutional memory not preserved elsewhere), the breadcrumb points to an existing or new learning file.

The per-rule decision is captured in the PR description for reviewer challenge.

### FR4: Threshold-rule update

`cq-agents-md-why-single-line` is updated:

- **Target: ≤ 32,000 bytes** (80% of Claude Code's 40k warn).
- **Hard fail: > 40,000 bytes** (matches tool warn).
- Rule count becomes advisory, not normative.
- The `<!-- rule-threshold: 115 -->` sentinel is changed to `<!-- rule-byte-threshold: 32000 -->` and synced between `AGENTS.md` and `plugins/soleur/skills/compound/SKILL.md` step 8 via `scripts/lint-agents-compound-sync.sh`.

### FR5: Pre-merge verification

Before the PR ships:

- `wc -c AGENTS.md` < 32,000.
- `bash scripts/lint-rule-ids.py` exits 0.
- `bash scripts/lint-agents-compound-sync.sh` exits 0.
- Each retired rule's breadcrumb is navigable (file exists OR replacement rule ID exists in `AGENTS.md`).

## Technical Requirements

### TR1: Rule-ID immutability preserved

Retired IDs in `scripts/retired-rule-ids.txt` are never reused. `lint-rule-ids.py` fails on any attempt to reintroduce a retired ID as an active rule. `cq-rule-ids-are-immutable` text is amended with one sentence referencing the allowlist mechanism.

### TR2: Deletion is non-destructive to learning content

The delete pass may NOT remove any learning file content. Breadcrumbs point to existing learning files where possible; when a learning file doesn't exist for a deleted rule, the breadcrumb points to the retired-ids entry itself (self-contained one-line justification).

### TR3: Compatibility with existing tooling

- `scripts/rule-metrics-aggregate.sh` must continue to run without crashing against the new AGENTS.md + retired-rule-ids.txt.
- `scripts/rule-prune.sh --dry-run` must continue to run without crashing (its output remains unusable until telemetry is fixed separately, but it must not error).
- `compound` skill step 8 reads the new byte threshold from the sentinel.

### TR4: Single atomic PR

All changes ship in one PR on branch `feat-agents-md-shrink`. Partial merges (e.g., delete pass without allowlist landed) leave the repo in a failing-lint state. The PR must be mergeable as a unit.

### TR5: Deletion pass safety procedure

Litmus application follows the procedure in the brainstorm doc §Implementation Notes: (i) read rule + `**Why:**`; (ii) test "discoverable?"; (iii) if ambiguous, KEEP (bias toward preservation); (iv) document each decision. A KEEP-biased litmus prevents over-shrinking. If fewer than 25 rules fail the litmus, the 32k target is treated as advisory — accept a smaller shrink rather than over-delete.

### TR6: Audit trail

The PR description includes a table with one row per retired rule: `| rule-id | action (deleted / pointer-migrated / kept) | rationale | breadcrumb |`. Reviewers can challenge individual calls without re-running the litmus manually.

## Success Criteria

- `AGENTS.md` byte size ≤ 32,000.
- `scripts/lint-rule-ids.py` green against the new state.
- `scripts/retired-rule-ids.txt` created, populated, and linter-validated.
- `wg-every-session-error-must-produce-either` text includes the discoverability litmus.
- `cq-agents-md-why-single-line` reflects bytes-only target.
- Issue #2762 closed by this PR.
- Follow-up telemetry-fix issue filed before merge (captures non-goal explicitly).
- Claude Code performance warning no longer fires on a fresh session.
- No learning file content destroyed.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Litmus applied too aggressively, deleting load-bearing rules | KEEP bias in TR5 (ambiguous → keep); per-rule review trail in TR6 |
| New rule inflow continues at 4.7/day, refilling budget in weeks | FR2 litmus amendment; compound step 8 applies it at rule-promotion time |
| Telemetry remains broken long-term, blocking future automated pruning | Non-goal explicitly tracked in follow-up issue; next shrink cycle addresses it |
| Retired rule's learning never surfaces again when the class recurs | Breadcrumbs in retired-rule-ids.txt; grep-able IDs remain findable |
| PR becomes too large to review | Delete pass organized by rule section; PR body table in TR6 makes per-rule review tractable |
| Pointer-migrated rules from PR #2754 get deleted, breaking cross-cutting discoverability | Re-apply litmus to those rules; conditional-firing pointers stay |

## References

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md`
- **Prior brainstorm:** `knowledge-base/project/brainstorms/2026-04-21-agents-md-rule-threshold-brainstorm.md`
- **Prior PR:** #2754 (MERGED) — 100→115 raise, +21 byte net pointer migration
- **Load-bearing unblock:** #2762 (OPEN) — retired-ids allowlist
- **Related open:** #2327 (stale audit), #2581, #2720
- **Key learnings:** `2026-02-25-lean-agents-md-gotchas-only.md`, `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`, `2026-04-18-agents-md-byte-budget-and-why-compression.md`
- **Files changed (preliminary):** `AGENTS.md`, `scripts/lint-rule-ids.py`, `scripts/retired-rule-ids.txt` (new), `scripts/lint-agents-compound-sync.sh`, `plugins/soleur/skills/compound/SKILL.md` (step 8 byte threshold)
