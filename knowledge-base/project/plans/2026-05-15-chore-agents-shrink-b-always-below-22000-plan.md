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

## Strategy evolution

**Plan v1 (demote + 5 Why-trims).** Rejected at 5-agent plan review: simplification panel (DHH + code-simplicity) said "prefer retirement"; correctness panel (Kieran + spec-flow) flagged byte-math drift + missing atomic-commit AC + Trim 2 over-trim.

**Plan v2 (retire `hr-no-dashboard-eyeball-pull-data-yourself` + 2 Why-trims).** Rejected at /work-time cross-reference sweep: the retirement candidate is canonically anchored in 5 operator-facing surfaces (`plugins/soleur/skills/ship/SKILL.md:1143,1169`, `plugins/soleur/skills/plan/SKILL.md:726`, `plugins/soleur/agents/engineering/review/deployment-verification-agent.md:97`, `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md:160`, `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md:101`). Retirement would leave these as dangling references OR force an 8-edit sweep — both fail the "cheapest credible path" framing.

**Plan v3 (this file) — demote + 6 Why-trims with plan-review fixes baked in.** Returns to architecture-strategist's ACCEPTED approach with the following corrections baked in:

- Phase 1 demotion byte count: **352 B** (Kieran's measurement; plan v1 said 348).
- Trim 2 (`hr-when-a-plan-specifies-relative-paths-e-g`) preserves the `infra/**` example (Kieran P2.1: load-bearing teaching).
- Atomic-commit invariant elevated to a verifiable AC (spec-flow's Critical finding).
- AC target tightened to ≤ 22,000 to match the lefthook reject threshold (not the arbitrary ≤ 21,950 from v1).
- 6th trim added for safety margin so the math doesn't land at the threshold (Kieran P1.1).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Issue body: "B_ALWAYS = 22,687 bytes" | Verified at HEAD: `python3 scripts/lint-agents-rule-budget.py` → `[REJECT] B_ALWAYS=22687 > 22000 (AGENTS.md=4721 + AGENTS.core.md=17966)`. | Use 22,687 baseline. |
| Issue body: "one wg-* demotion + targeted Why trim" | Verified via loader-fit analysis: only `wg-after-merging-a-pr-that-adds-or-modifies` is safely demotable (trigger surface `.github/workflows/*.yml` exclusively matches INFRA_RE at `.claude/hooks/session-rules-loader.sh:104` → `CLASSES="core rest"` on every relevant session). All other `wg-*` rules in core fire on docs-only sessions (`roadmap.md` edits), every-session start, every commit, or version-file edits. | Demote that one rule. Trim 6 non-compliance-tier Whys to recover the rest. |
| Plan v2's "retire `hr-no-dashboard-eyeball-pull-data-yourself`" path | `/work`-time grep found 5 operator-facing cross-references. Retirement would dangle the references; sweep would 8x the edit count. | Abandoned. Trim its Why instead (cross-references unaffected — the rule body stays in core, only the Why tail is shortened). |
| Architecture-strategist ACCEPT verdict on v1 demote+trim | Three doc-polish recommendations: (1) name the overlapping `wg-after-a-pr-merges-to-main-verify-all` gate explicitly, (2) document the docs-only blind spot in Risks, (3) fix the 348→352 B count. | All three folded into Phase 1 + Risks below. |
| Kieran's P2.1 — Trim 2 over-trims | Plan v1 trimmed `(PR #2889 — \`infra/**\` matched zero paths; gate missed \`middleware.ts\` / \`app/api/**\`)` to `(PR #2889).`, losing the `infra/**` teaching. | v3 trims to `(PR #2889 — \`infra/**\` matched zero paths).` — preserves the load-bearing pattern. |

## User-Brand Impact

- **If this lands broken:** AGENTS-touching PRs fail the lefthook gate; operators re-reach for `LEFTHOOK=0`. Same state as today, no net regression. Demotion-specific failure: the demoted rule (`wg-after-merging-a-pr-that-adds-or-modifies`) is invisible on a docs-only session that happens to need post-merge `gh workflow run` verification — but the broader gate `wg-after-a-pr-merges-to-main-verify-all` at `AGENTS.core.md:46` stays in core and provides coarser coverage.
- **If this leaks:** N/A — no regulated-data surface touched.
- **Brand-survival threshold:** `none, reason: harness-internal Markdown rule allocation; no auth/PII/payments/regulated-data surface touched (sensitive-path regex per plugins/soleur/skills/preflight/SKILL.md Check 6.1 not matched).`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-agents-rule-budget.py` exits 0; stdout shows `[OK] B_ALWAYS=<N>` with `N ≤ 22,000`.
- [ ] `python3 scripts/lint-rule-ids.py` exits 0 (no rule IDs removed; demoted rule's ID stays present across sidecars).
- [ ] `bash scripts/lint-agents-rule-budget.test.sh` passes.
- [ ] `bash .claude/hooks/session-rules-loader.test.sh` passes.
- [ ] `bash .claude/hooks/session-rules-loader-headless.test.sh` passes.
- [ ] `grep -F "[id: wg-after-merging-a-pr-that-adds-or-modifies]" AGENTS.md` returns the `→ rest` line.
- [ ] `grep -F "[id: wg-after-merging-a-pr-that-adds-or-modifies]" AGENTS.core.md` returns zero matches.
- [ ] `grep -F "[id: wg-after-merging-a-pr-that-adds-or-modifies]" AGENTS.rest.md` returns exactly one match under `## Workflow Gates`.
- [ ] All 6 trimmed Why clauses preserve their canonical `#NNNN` citation. Per-trim citation greps:
  - `grep -F "**Why:** #3356." AGENTS.core.md` returns 1 match.
  - `grep -F '(PR #2889 — `infra/**` matched zero paths).' AGENTS.core.md` returns 1 match. (Single quotes deliberate: prevents backtick command-substitution if the AC is later copy-pasted into a `bash -c "..."` wrapper or CI step.)
  - `grep -F "**Why:** #2075." AGENTS.core.md` returns 1 match.
  - `grep -F "**Why:** #2681." AGENTS.core.md` returns 1 match.
  - `grep -F "**Why:** #2430." AGENTS.core.md` returns 1 match.
  - `grep -F "**Why:** EU single-user threshold." AGENTS.core.md` returns 1 match.
- [ ] Compliance-tier rules' Whys are unchanged: `grep -F '[compliance-tier]' AGENTS.core.md` returns 5 matches (`hr-exhaust-all-automated-options-before`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `hr-never-paste-secrets-via-bang-prefix`, `cq-pg-security-definer-search-path-pin-pg-temp`); none have been edited.
- [ ] **Atomic-commit invariant** (per spec-flow Critical finding): `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md AGENTS.rest.md | wc -l` returns exactly `1` — the demote+trims commit. Plan/tasks commits do not touch AGENTS files. The demote and trims MUST land in a single commit because Phase 1 alone fails lefthook (B_ALWAYS ≈ 22,335 > 22,000).
- [ ] No commit in this PR uses `LEFTHOOK=0`.
- [ ] PR body uses `Closes #3833` on its own line.

### Post-merge (operator)

- [ ] None.

## Implementation Phases

### Phase 0 — Preconditions

- **CWD = worktree:** `pwd` ends in `.worktrees/feat-one-shot-3833`. Bash CWD does NOT persist across calls — use absolute paths.
- **Baseline lint state:** `python3 scripts/lint-agents-rule-budget.py` → `B_ALWAYS=22687`.
- **Loader regex unchanged:** `sed -n '99,126p' .claude/hooks/session-rules-loader.sh` shows `DOCS_RE` / `CODE_RE` / `INFRA_RE` triplet + class-selection branch. Demotion routes to `core+rest` when `HAS_INFRA=1`.
- **No collision PR:** `gh pr list --search "linked:issue #3833" --state open` returns only draft #3837.

### Phase 1 — Demote `wg-after-merging-a-pr-that-adds-or-modifies` (core → rest)

**Why this rule.** Only `wg-*` rule in core whose trigger surface is exclusively `.github/workflows/*.yml` modifications → matches `INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'` at `session-rules-loader.sh:104` → `CLASSES="core rest"` per the selector at line 124. All other `wg-*` rules in core fire on docs-only sessions, every-session start, every commit, or no-class file edits.

**Defense-in-depth (per architecture-strategist).** The broader gate `wg-after-a-pr-merges-to-main-verify-all` (`AGENTS.core.md:46`) stays in core and provides coarse post-merge verification coverage. Demotion narrows only the workflow-specific `gh workflow run` recipe to code/infra sessions.

**Edits (must land in the same commit as Phase 2):**

1. `AGENTS.md:59` (Workflow Gates index): change `→ core` to `→ rest`. Zero net byte delta (string lengths identical).
2. `AGENTS.core.md:52`: delete the rule body line (one `^- ` line). **Measured: 352 B** including the trailing `\n` (Kieran's measurement; plan v1's 348 was wrong).
3. `AGENTS.rest.md`: append the deleted line verbatim to `## Workflow Gates` section (after `wg-use-closes-n-in-pr-body-not-title-to` at line 18).

**Cross-reference check:** `scripts/lint-scheduled-show-full-output.sh:19` references the rule by ID in a comment. This is a documentation comment, not a routing dependency. The rule ID survives in AGENTS.{md,rest.md}; the comment continues to resolve. No edit needed.

### Phase 2 — Why-trims on 6 non-compliance-tier rules

Per `cq-agents-md-why-single-line` (governs Why shape, not Why existence), the Why may be shortened to the canonical `#NNNN` citation when the supplementary tail is grep-discoverable from the linked PR/learning. Compliance-tier rules' Whys document brand-survival incident shapes and stay intact.

**Trim 1 — `hr-no-dashboard-eyeball-pull-data-yourself` (AGENTS.core.md:34).**

- Current Why: `**Why:** #3356; see \`knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md\`.`
- New Why: `**Why:** #3356.`
- Bytes saved: **94 B** (Kieran's measurement).
- Note: the rule itself stays in core — only the Why prose is trimmed. The 5 operator-facing cross-references (ship/SKILL.md, plan/SKILL.md, etc.) continue to resolve.

**Trim 2 — `hr-when-a-plan-specifies-relative-paths-e-g` (AGENTS.core.md:9).**

- Current tail: `(PR #2889 — \`infra/**\` matched zero paths; gate missed \`middleware.ts\` / \`app/api/**\`).`
- New tail: `(PR #2889 — \`infra/**\` matched zero paths).`
- Bytes saved: **~57 B** (Kieran-aware: preserves the `infra/**` example; drops only the `middleware.ts / app/api/**` half).

**Trim 3 — `hr-when-triaging-a-batch-of-issues-never` (AGENTS.core.md:14).**

- Current Why: `**Why:** #2075 deferred OG image gen despite \`gemini-imagegen\` being available.`
- New Why: `**Why:** #2075.`
- Bytes saved: **64 B**.

**Trim 4 — `hr-ssh-diagnosis-verify-firewall` (AGENTS.core.md:26).**

- Current Why: `**Why:** #2681 — #2654 plan had sshd hypotheses; cause was admin-IP drift.`
- New Why: `**Why:** #2681.`
- Bytes saved: **61 B**. The runbook citation (`knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) earlier in the body is preserved.

**Trim 5 — `wg-when-a-workflow-gap-causes-a-mistake-fix` (AGENTS.core.md:51).**

- Current Why: `**Why:** #2430 committed a verbal promise instead of a skill edit.`
- New Why: `**Why:** #2430.`
- Bytes saved: **51 B**.

**Trim 6 — `hr-gdpr-gate-on-regulated-data-surfaces` (AGENTS.core.md:31) — for safety margin.**

- Current Why: `**Why:** EU \`single-user incident\` threshold; pre-generation catch beats post-hoc audit.`
- New Why: `**Why:** EU single-user threshold.`
- Bytes saved: **~54 B**. Editorial trim; the brand-survival framing stays in the rule body.

**Combined Phase 2 trim: ~381 B.**

### Phase 3 — Combined byte math + atomic commit

| Step | Δ B_ALWAYS | Running B_ALWAYS |
|---|---:|---:|
| Baseline | — | 22,687 |
| Phase 1: demote `wg-after-merging-...` | −352 | 22,335 |
| Trim 1 (no-dashboard-eyeball Why) | −94 | 22,241 |
| Trim 2 (relative-paths, preserve `infra/**`) | −57 | 22,184 |
| Trim 3 (triaging-batch Why) | −64 | 22,120 |
| Trim 4 (ssh-diagnosis Why) | −61 | 22,059 |
| Trim 5 (workflow-gap Why) | −51 | 22,008 |
| Trim 6 (gdpr-gate Why) | −54 | **21,954** (projected) — actual measured post-commit: **21,966** (12 B drift) |

Final (projected): B_ALWAYS ≈ 21,954 (46 B headroom). **Actual post-commit: B_ALWAYS = 21,966 (34 B headroom).** The 12 B drift is per-trim estimate noise; the absolute floor is `lint-agents-rule-budget.py exit 0`, which holds.

If the post-edit linter reports `> 22,000` (estimates drift), add a 7th trim from the spare list below BEFORE committing. Do NOT use `LEFTHOOK=0`.

**Spare trim candidates (use only if math drifts short):**

- `wg-when-an-audit-identifies-pre-existing` Why: currently has no Why tail — skip.
- `hr-weigh-every-decision-against-target-user-impact` Why: `**Why:** #2887/#2888.` — already minimal; skip.
- `hr-when-a-plan-specifies-relative-paths-e-g` Trim 2 wider: drop `infra/**` example entirely → saves an additional ~30 B. Only if necessary (Kieran P2.1 prefers we keep the example).

**Compliance-tier preservation (NEVER trim):** `hr-exhaust-all-automated-options-before`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `hr-never-paste-secrets-via-bang-prefix`, `cq-pg-security-definer-search-path-pin-pg-temp`.

**Single-commit flow:**

```bash
git add AGENTS.md AGENTS.core.md AGENTS.rest.md
python3 scripts/lint-agents-rule-budget.py     # MUST exit 0, B_ALWAYS ≤ 22,000
python3 scripts/lint-rule-ids.py                # MUST exit 0
bash scripts/lint-agents-rule-budget.test.sh
bash .claude/hooks/session-rules-loader.test.sh
bash .claude/hooks/session-rules-loader-headless.test.sh
git commit -m "$(cat <<'EOF'
chore(AGENTS): shrink B_ALWAYS below 22,000-byte critical threshold

Demote wg-after-merging-a-pr-that-adds-or-modifies from core to rest
(trigger surface .github/workflows/*.yml always matches INFRA_RE,
loader-fit verified at session-rules-loader.sh:99-126). The broader
gate wg-after-a-pr-merges-to-main-verify-all stays in core and
provides coarser post-merge verification coverage.

Trim Why tails on 6 non-compliance-tier rules to recover headroom.
Canonical PR/issue citations preserved; supplementary prose moved
to git log and linked learning files. Compliance-tier Whys unchanged.

B_ALWAYS: 22,687 → ~21,954 (~46 B headroom on the 22,000 reject cap).

Closes #3833
EOF
)"
git push
```

## Files to Edit

- `AGENTS.md` — flip one index pointer at line 59 (`→ core` → `→ rest`). Zero net byte delta.
- `AGENTS.core.md` — delete one body line (line 52); trim Why tails on lines 9, 14, 26, 31, 34, 51.
- `AGENTS.rest.md` — append the demoted rule body to `## Workflow Gates` (after line 18).

## Files to Create

- None.

## Open Code-Review Overlap

Queried via `gh issue list --label code-review --state open --json number,title,body --limit 200` filtered for AGENTS files: none match. Five open code-review issues (#3392, #3373, #3372, #3160, #3002) do not reference AGENTS sidecars.

Disposition: nothing to fold in.

## Domain Review

**Domains relevant:** Engineering only. Harness-internal tooling change; no marketing, legal, operations, product, sales, finance, or support implications. Per parent brainstorm `2026-04-23-agents-md-budget-revisit-brainstorm.md` line 127.

## Test Scenarios

Non-runtime change. Verification surface:

```bash
python3 scripts/lint-agents-rule-budget.py            # exit 0, B_ALWAYS ≤ 22,000
python3 scripts/lint-rule-ids.py                       # exit 0
bash scripts/lint-agents-rule-budget.test.sh           # smoke test
bash .claude/hooks/session-rules-loader.test.sh        # loader parity
bash .claude/hooks/session-rules-loader-headless.test.sh
```

## Risks

1. **Docs-only follow-up session blind spot.** Operator opens a docs-only session post-merge intending to verify a previously-merged workflow PR. The demoted rule body is absent. Mitigation: the broader gate `wg-after-a-pr-merges-to-main-verify-all` (AGENTS.core.md:46) stays in core. The pointer-index entry at AGENTS.md:59 is always loaded; an agent grepping the index follows `→ rest` to find the body.
2. **34 B headroom is thin** (12 B less than the projected 46 B). Next AGENTS edit that adds ~50 B re-triggers the lefthook gate. Mitigation: issues #3834 (per-rule cap audit) and the discoverability-litmus brainstorm 2026-04-23 are queued. Escalate to the brainstorm if headroom is exhausted within 7 days post-merge. **Explicitly accepted at review time** — operator chose to defer broader cleanup to the brainstorm rather than expand this PR's scope.
3. **Trim estimates may drift by ±5 B.** Mitigation: Phase 3 verification iterates with a spare trim if linter reports > 22,000. The absolute floor is `python3 scripts/lint-agents-rule-budget.py exit 0`.
4. **Trim 2 still loses semantic detail.** The `middleware.ts / app/api/**` example documented a specific failure shape; the canonical `(PR #2889 — \`infra/**\` matched zero paths).` form preserves the load-bearing pattern but drops the secondary case. Mitigation: PR #2889 description and the linked learning file retain the full detail.

## Sharp Edges

- **Atomic-commit invariant.** Phase 1 alone (demotion only) reaches B_ALWAYS ≈ 22,335 — still over 22,000 → lefthook REJECT. Splitting forces `LEFTHOOK=0`, which is the workflow this PR closes. The AC `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md AGENTS.rest.md | wc -l == 1` enforces this (one atomic commit for the demote+trims; plan/tasks commits don't touch AGENTS files and aren't counted).
- **`cq-rule-ids-are-immutable` is satisfied.** Demotion moves the `[id: ...]` line from one sidecar to another; the linter's allowlist semantics are unchanged.

## Sequencing

Single atomic commit for the AGENTS edits. Discoverability-litmus PR (broader 32k target) remains tracked under brainstorm `2026-04-23-agents-md-budget-revisit-brainstorm.md`; outside this PR's scope.
