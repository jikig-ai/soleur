---
title: "chore(AGENTS): shrink B_ALWAYS below 22,000-byte critical threshold"
type: chore
date: 2026-05-15
issue: "#3833"
branch: feat-one-shot-3833
lane: cross-domain
requires_cpo_signoff: false
---

# chore(AGENTS): shrink B_ALWAYS below 22,000-byte critical threshold

## Overview

`scripts/lint-agents-rule-budget.py` is in REJECT state on `main`: B_ALWAYS = 22,687 B > 22,000 B cap (warn ≥ 20,000). PR #3808 shipped 4 commits with `LEFTHOOK=0` bypass; the workaround is unsustainable and the issue exists to close it.

Per brainstorm `2026-04-23-agents-md-budget-revisit-brainstorm.md` (decided): "Full deletion via `retired-rule-ids.txt` is the only byte-positive path. Pointer-migration is byte-neutral (PR #2754 measured +21 B net). Demotion is reversible relocation but adds surface area." Plan v1 proposed demote + 5 Why-trims (8 surface edits, byte math ended at 21,981 B — over the AC). 5-agent plan review converged: simplification panel (DHH + code-simplicity) said REVISE-prefer-retirement; correctness panel (Kieran + spec-flow) said REVISE-byte-math-drift. **Plan v2 (this file) pivots to retirement + small trim — fewer surface edits, dissolves the byte-math drift, aligns with the brainstorm.**

## Strategy

**Retire `hr-no-dashboard-eyeball-pull-data-yourself`** (AGENTS.core.md:34, 582 B body + AGENTS.md:25 pointer ≈ 53 B = ~635 B saved). Discoverability-litmus rationale below.

**Plus Why-tail trim on two rules** for safety margin:

- `hr-ssh-diagnosis-verify-firewall` (AGENTS.core.md:26): trim Why tail to `**Why:** #2681.` (≈ 61 B saved). The runbook citation (`knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) IS preserved in the rule body — that's the load-bearing reference, not the Why prose.
- `hr-when-triaging-a-batch-of-issues-never` (AGENTS.core.md:14): trim Why tail to `**Why:** #2075.` (≈ 64 B saved). The named tools (`gemini-imagegen`, `frontend-design`, `copywriter`, `pencil` MCP) stay in the rule body.

**Combined savings: ~760 B → B_ALWAYS ≈ 21,927 (≈ 73 B headroom on the 22,000 cap).**

## Discoverability litmus — `hr-no-dashboard-eyeball-pull-data-yourself`

Per brainstorm 2026-04-23: "Can the agent discover this on its own by reading the code, running the command, or trying it? If yes, delete." Applied to this rule:

- **The rule:** "When a monitoring/recovery/health check returns a technical signal that needs interpretation, never punt to operator dashboard-watching or 'human-judgment' if the underlying data is API-accessible. Per `hr-exhaust-all-automated-options-before`, pull readings via Management APIs/MCP/CLI…"
- **Subsumption.** The operative prescription ("don't manual / dashboard if APIs exist") is the same prescription as `hr-exhaust-all-automated-options-before` (compliance-tier, stays in core). The dashboard-eyeball rule is a more specific phrasing of the broader principle.
- **PR #3808 precedent.** The rule was already trimmed from 1,150 B → 582 B by PR #3808. Plan v1's Risk #5 explicitly flagged "this PR is the LAST cheap trim on that rule" — further trimming would gut the operative prescription. Retirement is more honest than incremental gutting.
- **Learning-file backstop.** The retired-rule breadcrumb in `scripts/retired-rule-ids.txt` will point at `knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md`. The institutional knowledge is preserved.
- **Discoverability.** When an agent reads a runbook that says "check Grafana", the alternative path (Management API / MCP / CLI per `hr-exhaust-all-automated-options-before`) is in-context via the broader rule. The dashboard-eyeball rule's incremental teaching is editorial, not load-bearing.

Conclusion: retire.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Issue body: "B_ALWAYS = 22,687 bytes" | Verified: `python3 scripts/lint-agents-rule-budget.py` outputs `[REJECT] B_ALWAYS=22687 > 22000 (AGENTS.md=4721 + AGENTS.core.md=17966)`. | Use 22,687 as the baseline. |
| Issue body: "demote a wg-* rule" | Demote-only insufficient (≤ 352 B savings on the largest demote candidate, well under 688 B). Issue body also offers retirement path; brainstorm 2026-04-23 endorses retirement. | Pivot to retirement of one large rule + small Why-trim. |
| Brainstorm 2026-04-23: "Approach D: amend `wg-every-session-error-must-produce-either` with discoverability litmus + retire 25 rules to hit 32k target" | This PR ships ONE retirement against the narrower 22,000 hard-fail target. Broader pass remains under brainstorm 2026-04-23. | Apply the discoverability litmus to one rule only here. Defer the wholesale pass. |
| Plan v1 (this file pre-pivot): "demote `wg-after-merging-a-pr-that-adds-or-modifies` + 5 Why-trims" | Kieran measurement: combined savings = 706 B, lands at 21,981 — over the proposed ≤ 21,950 AC by 31 B; 8 surface edits; Trim 2 was load-bearing-lossy. | Discarded. v2 retirement + 2 trims is structurally simpler and dissolves the math drift. |

## User-Brand Impact

- **If this lands broken:** an AGENTS-touching PR fails the lefthook gate (same state as today). No user-facing failure mode.
- **If this leaks:** N/A — no regulated-data surface touched.
- **Brand-survival threshold:** `none, reason: harness-internal Markdown rule allocation; no auth/PII/payments/regulated-data surface touched (sensitive-path regex per plugins/soleur/skills/preflight/SKILL.md Check 6.1 not matched).`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-agents-rule-budget.py` exits 0; stdout shows `[OK] B_ALWAYS=<N>` with `N ≤ 22,000`.
- [ ] `python3 scripts/lint-rule-ids.py` exits 0 (the retired ID is correctly listed in `scripts/retired-rule-ids.txt` and absent from active AGENTS sidecars).
- [ ] `bash scripts/lint-agents-rule-budget.test.sh` passes.
- [ ] `bash .claude/hooks/session-rules-loader.test.sh` passes.
- [ ] `bash .claude/hooks/session-rules-loader-headless.test.sh` passes.
- [ ] `grep -F "hr-no-dashboard-eyeball-pull-data-yourself" AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` returns zero matches.
- [ ] `grep -F "hr-no-dashboard-eyeball-pull-data-yourself" scripts/retired-rule-ids.txt` returns exactly one match with the format `<id> | 2026-05-15 | PR #<N> | knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md`.
- [ ] `grep -F "**Why:** #2681." AGENTS.core.md` returns exactly one match (Trim 1 citation preserved).
- [ ] `grep -F "**Why:** #2075." AGENTS.core.md` returns exactly one match (Trim 2 citation preserved).
- [ ] `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md scripts/retired-rule-ids.txt | wc -l` returns exactly `1` — the retirement + trims land in a single atomic commit, NOT split. (Per spec-flow finding: atomic-commit invariant promoted to verifiable AC. Splitting would force a `LEFTHOOK=0` bypass on the intermediate state.)
- [ ] No commit in this PR uses `LEFTHOOK=0`.
- [ ] PR body uses `Closes #3833` on its own line.

### Post-merge (operator)

- [ ] None.

## Implementation Phases

### Phase 0 — Preconditions

- **CWD = worktree:** `pwd` ends in `.worktrees/feat-one-shot-3833`. Subsequent Bash calls use absolute paths or `cd … && <cmd>`.
- **Baseline lint state:** re-run `python3 scripts/lint-agents-rule-budget.py`; confirm `B_ALWAYS=22687`. If shifted, recompute Phase 1+2's running totals.
- **Retired-rule-ids format:** read `scripts/retired-rule-ids.txt` header (lines 1-22) to confirm the entry format: `<rule-id> | <YYYY-MM-DD> | <PR #NNNN or -> | <breadcrumb>`.
- **No collision PR:** `gh pr list --search "linked:issue #3833" --state open` returns only the draft (#3837) opened for this worktree.

### Phase 1 — Retire `hr-no-dashboard-eyeball-pull-data-yourself`

Edits (atomic, must land in a single commit):

1. **`AGENTS.md`:** delete the index pointer line at `AGENTS.md:25` (`- [id: hr-no-dashboard-eyeball-pull-data-yourself] → core`). Net byte delta: −53 B from AGENTS.md.
2. **`AGENTS.core.md`:** delete the rule body line at `AGENTS.core.md:34`. Net byte delta: −583 B from core (582 + 1 nl).
3. **`scripts/retired-rule-ids.txt`:** append one line:

    ```text
    hr-no-dashboard-eyeball-pull-data-yourself | 2026-05-15 | PR #<this-PR-N> | knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md
    ```

    The `<this-PR-N>` placeholder MUST be replaced with the actual PR number (draft PR #3837 or its successor) at the commit step. The `lint-rule-ids.py` linter accepts `-` as a placeholder when no PR is known, but a concrete number is preferred for grep-discovery.

**Cross-reference sweep before delete:**

```bash
grep -rln "hr-no-dashboard-eyeball-pull-data-yourself" --include='*.md' --include='*.sh' --include='*.py' --include='*.ts' . | grep -v knowledge-base/project/learnings | grep -v knowledge-base/project/brainstorms | grep -v knowledge-base/project/plans | grep -v knowledge-base/project/specs
```

Expected matches: `AGENTS.md`, `AGENTS.core.md`, `scripts/retired-rule-ids.txt` (after the append). If any other file references the rule ID, fold its update into this PR or scope-out with rationale.

### Phase 2 — Why-trim on 2 rules

**Trim 1 — `hr-ssh-diagnosis-verify-firewall` (AGENTS.core.md:26).**

- Current Why: `**Why:** #2681 — #2654 plan had sshd hypotheses; cause was admin-IP drift.`
- New Why: `**Why:** #2681.`
- Bytes saved: ≈ 61 B. The runbook reference (`knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) earlier in the body is the load-bearing pointer; the Why prose was supplementary.

**Trim 2 — `hr-when-triaging-a-batch-of-issues-never` (AGENTS.core.md:14).**

- Current Why: `**Why:** #2075 deferred OG image gen despite \`gemini-imagegen\` being available.`
- New Why: `**Why:** #2075.`
- Bytes saved: ≈ 64 B. The named tools list earlier in the body (`gemini-imagegen`, `frontend-design`, `copywriter`, `pencil` MCP) carries the operative knowledge.

**Trim criterion (uniform across both):** the Why retains the canonical `#NNNN` token so a grep against `git log` or the linked PR description recovers the full incident shape. The rule's operative prescription (the imperative clause before `[id: ...]`) is unchanged. Compliance-tier rules are NOT trimmed.

### Phase 3 — Verify and commit

Combined byte math:

| Step | Δ B_ALWAYS | Running B_ALWAYS |
|---|---:|---:|
| Baseline | — | 22,687 |
| Phase 1: retire (−583 core, −53 index) | −636 | 22,051 |
| Phase 2 Trim 1 (ssh-firewall Why) | −61 | 21,990 |
| Phase 2 Trim 2 (triaging-batch Why) | −64 | **21,926** |

Final: B_ALWAYS ≈ 21,926. **74 B headroom on the 22,000 cap.** If the linter reports > 22,000 (estimates drift), add a 3rd Why-trim from the spare list below before pushing — do NOT use `LEFTHOOK=0`.

Single-commit flow:

```bash
git add AGENTS.md AGENTS.core.md scripts/retired-rule-ids.txt
python3 scripts/lint-agents-rule-budget.py  # MUST exit 0, B_ALWAYS ≤ 22,000
python3 scripts/lint-rule-ids.py             # MUST exit 0
bash scripts/lint-agents-rule-budget.test.sh
bash .claude/hooks/session-rules-loader.test.sh
bash .claude/hooks/session-rules-loader-headless.test.sh
git commit -m "$(cat <<'EOF'
chore(AGENTS): shrink B_ALWAYS below 22,000-byte critical threshold

Retire hr-no-dashboard-eyeball-pull-data-yourself per the discoverability
litmus (brainstorm 2026-04-23): the operative prescription is subsumed by
hr-exhaust-all-automated-options-before; institutional knowledge preserved
in retired-rule-ids.txt and the linked learning file.

Trim Why tails on hr-ssh-diagnosis-verify-firewall and
hr-when-triaging-a-batch-of-issues-never (canonical #NNNN citations
preserved; supplementary prose trimmed).

B_ALWAYS: 22,687 → ~21,926 (~74 B headroom on the 22,000 reject cap).

Closes #3833
EOF
)"
git push
```

**Spare trim candidates (if byte math comes up short):**

- `hr-gdpr-gate-on-regulated-data-surfaces` Why: `**Why:** EU \`single-user incident\` threshold; pre-generation catch beats post-hoc audit.` → `**Why:** EU single-user threshold.` saves ≈ 54 B. Editorial; safe.
- `wg-when-a-workflow-gap-causes-a-mistake-fix` Why: `**Why:** #2430 committed a verbal promise instead of a skill edit.` → `**Why:** #2430.` saves ≈ 51 B.

**Compliance-tier preservation (do NOT trim):** `hr-exhaust-all-automated-options-before`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `hr-never-paste-secrets-via-bang-prefix`, `cq-pg-security-definer-search-path-pin-pg-temp`. These document brand-survival incident shapes; Whys are load-bearing.

## Files to Edit

- `AGENTS.md` — delete one index pointer line (line 25).
- `AGENTS.core.md` — delete one body line (line 34); trim Why tails on lines 14 and 26.
- `scripts/retired-rule-ids.txt` — append one line.

## Files to Create

- None.

## Open Code-Review Overlap

Queried via `gh issue list --label code-review --state open --search "..." --json number,title,body --limit 200` and filtered for `AGENTS.md`, `AGENTS.core.md`, `AGENTS.rest.md`, `retired-rule-ids.txt`: none. Open code-review issues (#3392, #3373, #3372, #3160, #3002) do not reference these files.

Disposition: nothing to fold in.

## Domain Review

**Domains relevant:** Engineering only. Harness-internal tooling change; no marketing, legal, operations, product, sales, finance, or support implications.

Parent brainstorm `2026-04-23-agents-md-budget-revisit-brainstorm.md` (line 127+) reached the same scope determination: Engineering-only decision, no user-facing surface.

## Test Scenarios

Non-runtime change (Markdown sidecar edits). The verification surface is:

```bash
python3 scripts/lint-agents-rule-budget.py            # must exit 0, B_ALWAYS ≤ 22,000
python3 scripts/lint-rule-ids.py                       # must exit 0
bash scripts/lint-agents-rule-budget.test.sh           # smoke test
bash .claude/hooks/session-rules-loader.test.sh        # loader parity
bash .claude/hooks/session-rules-loader-headless.test.sh
```

Loader behavioral parity: the retired rule body no longer ships in any class's `additionalContext`. The pointer-index entry is also gone, so an agent grepping AGENTS.md for the ID finds zero matches (correct — the rule is retired). An agent grepping `scripts/retired-rule-ids.txt` finds the breadcrumb to the learning file.

## Risks

1. **Future planner relies on retired rule context.** Mitigation: breadcrumb in `retired-rule-ids.txt` points at the learning file; broader prescription survives in `hr-exhaust-all-automated-options-before`. Retired-rule-ids.txt is grep-discoverable.
2. **74 B headroom is thin.** Next AGENTS edit that adds ~75 B re-triggers the lefthook gate. Mitigation: issues #3834 (per-rule cap audit) and the discoverability-litmus brainstorm 2026-04-23 are queued; broader headroom buys via those PRs, not this one. If headroom is exhausted within 7 days post-merge, escalate to executing the brainstorm.
3. **Trim estimates may drift by ±5 B.** Mitigation: Phase 3 verification iterates with a spare-trim if linter reports > 22,000; the absolute floor is `python3 scripts/lint-agents-rule-budget.py exit 0`. Iteration is documented; the AC's atomic-commit invariant means iteration happens BEFORE the commit, not via a `LEFTHOOK=0` follow-up.
4. **Retirement is permanent per `cq-rule-ids-are-immutable`.** The retired ID cannot be re-used as an active rule. If the constraint resurfaces as load-bearing, a NEW rule with a NEW slug must be created (per `retired-rule-ids.txt` header lines 18-22). The breadcrumb in `retired-rule-ids.txt` provides the path back to the learning file for any future plan that needs to re-instantiate the constraint.

## Sharp Edges

- **Atomic commit invariant (load-bearing).** Phase 1 + Phase 2 must land in a single commit. Phase 1 alone (retirement only) reaches B_ALWAYS ≈ 22,051, still over 22,000 → lefthook REJECT. Splitting forces `LEFTHOOK=0`, which is the workflow this PR closes. The AC `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md scripts/retired-rule-ids.txt | wc -l == 1` enforces this.
- **`cq-rule-ids-are-immutable`** is satisfied: the retired ID is moved from active sidecars to `retired-rule-ids.txt`. `lint-rule-ids.py` recognizes the file as an allowlist for absent IDs.

## Sequencing

Single atomic commit. No follow-up PRs required for this issue.

Discoverability-litmus PR (broader 32k target, ~25 retirements) remains tracked under brainstorm `2026-04-23-agents-md-budget-revisit-brainstorm.md`; outside this PR's scope.
