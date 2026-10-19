# Plan: Shrink AGENTS.md via retired-ids allowlist + discoverability litmus

**Issue:** #2865 (Closes #2762)
**Branch:** `feat-agents-md-shrink`
**Worktree:** `.worktrees/feat-agents-md-shrink/`
**Draft PR:** #2862
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-agents-md-shrink/spec.md`

## Overview

Claude Code emits `⚠ Large AGENTS.md will impact performance (40.5k chars > 40.0k)`. AGENTS.md (113 rules / 40,654 bytes) is the sole always-loaded governance file. ETH Zurich research cited in `knowledge-base/project/learnings/2026-02-25-lean-agents-md-gotchas-only.md` shows always-loaded context adds 10-22% reasoning tokens / 15-20% per-turn cost — the warn is a proxy for this real cost.

Execute Approach D from the brainstorm: single PR landing (1) retired-ids allowlist in `scripts/lint-rule-ids.py` + new `scripts/retired-rule-ids.txt`, (2) discoverability-litmus amendment to `wg-every-session-error-must-produce-either`, (3) delete pass applying the litmus to all 113 existing rules, (4) bytes-only threshold update in `cq-agents-md-why-single-line`.

Plan simplified post-review (DHH + Kieran + code-simplicity): 3 phases, touched-rules-only audit table, 3 tests, no optional stretch, no second sentinel, bugs fixed.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `scripts/lint-rule-ids.py` exists | ✓ 102 lines; ID_RE mirrored in `scripts/rule-prune.sh` | Amend `removed = head_ids - current_ids` to subtract `retired_ids`. |
| `scripts/retired-rule-ids.txt` is new | ✓ does not exist | Create in Phase 1 with header comments. |
| `scripts/lint-agents-compound-sync.sh` exists | ✓ 35 lines; extracts `rule-threshold: N` sentinel | **No changes** — hardcode `37000` in both files (AGENTS.md + compound/SKILL.md). Review catches drift. |
| `compound/SKILL.md` step 8 has threshold sentinel | ✓ line 205 `<!-- rule-threshold: 115 -->` | Update warn message to use hardcoded `37000`; rule-count sentinel stays advisory. |
| Spec silent on existing tests | **Tests EXIST** at `tests/scripts/test_lint_rule_ids.py` (124 lines, 5 methods, stdlib `unittest`) | Extend existing file with 3 tests. |
| Pointer-migration saves bytes | **+21 bytes net** (PR #2754 measured) | Abandon pattern for always-invoked hooks/skills; keep minimal pointer only for conditional firing. |

**Rejected input:** `scripts/rule-audit.sh` reports 4 "MISSING" hook files — all 4 exist at paths the audit doesn't search (`.claude/hooks/lib/incidents.sh`, `plugins/soleur/hooks/browser-cleanup-hook.sh`, `scripts/lint-rule-ids.py`). Plan does NOT cite audit output as normative; direct litmus evaluation replaces it. See `knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `wc -c AGENTS.md` < 37,000 bytes (silences 40k warn with ~3k headroom).
- [ ] `wc -c AGENTS.md` < 40,000 bytes (regression guard matches tool warn).
- [ ] `python3 scripts/lint-rule-ids.py` exits 0.
- [ ] `bash scripts/lint-agents-compound-sync.sh` exits 0 (threshold sentinels synced — existing rule-count sentinel only).
- [ ] `python3 -m unittest tests.scripts.test_lint_rule_ids` — all tests green including 3 new allowlist tests.
- [ ] PR body contains per-rule decision table for **touched rules only** (deleted or pointer-migrated). Format: `| rule-id | action | rationale | breadcrumb |`. Reviewers challenge individual rows.
- [ ] Spec `spec.md` FR4 text updated to reflect 32k→37k TR5-advisory adjustment (see Phase 0).
- [ ] Issue #2762 closed via `Closes #2762` in PR body.
- [ ] No learning file content destroyed.

### Post-merge (operator)

- [ ] Fresh Claude Code session on `main` — warn does NOT fire.
- [ ] Confirm `scripts/rule-metrics-aggregate.sh` + `scripts/rule-prune.sh --dry-run` do not crash (may still emit `hit_count=0` per #2866; that's explicit non-goal).

**Numeric projection** (conservative, with reviewer-corrected litmus calls):

- 13 litmus deletes × mean 273 bytes ≈ −3,552 bytes
- 3 pointer deletes (always-invoked hooks/skills) ≈ −624 bytes
- Amendments (3 rule edits) ≈ +300–400 bytes
- **Net: ~−3,776 to −3,876 → final 36,680–36,880 bytes.** Under 37k target with ~120-320 bytes margin.

**Re-measure gate:** After Phase 1+2 land, re-run `wc -c AGENTS.md`. If margin < 200 bytes, identify one more delete candidate OR compress one oversized rule before Phase 3 delete pass locks.

## Files to Edit

- `AGENTS.md` — amend `wg-every-session-error-must-produce-either` (add litmus), `cq-agents-md-why-single-line` (bytes-only target + hardcoded 37000), `cq-rule-ids-are-immutable` (add allowlist sentence); delete ~13 rules per litmus + 3 pointer rules.
- `scripts/lint-rule-ids.py` — add `--retired-file` CLI flag; parse file, subtract retired IDs from `removed` set, detect reintroduction. ~15 lines added.
- `plugins/soleur/skills/compound/SKILL.md` — step 8 warn message: bump `40000 → 37000` literal; rule-count warn stays as advisory at 115.
- `tests/scripts/test_lint_rule_ids.py` — add 3 new unittest methods (see Phase 1.3).
- `knowledge-base/project/specs/feat-agents-md-shrink/spec.md` — FR4 text update (Phase 0).

## Files to Create

- `scripts/retired-rule-ids.txt` — allowlist file with header comment block + ~16 initial entries populated during Phase 2 delete pass.

## Open Code-Review Overlap

None. Checked via `gh issue list --label code-review --state open --json number,title,body --limit 200`; no match for the planned file list.

## Implementation Phases

### Phase 0: Spec reconciliation

- [ ] 0.1 Edit `knowledge-base/project/specs/feat-agents-md-shrink/spec.md` FR4 to record the 32k→37k TR5-advisory adjustment. Replace "Target: ≤ 32,000 bytes" with:

  > **Target: ≤ 37,000 bytes** (80% of Claude Code's 40k warn would be 32k, but pre-sample litmus yielded <25 failures triggering TR5 advisory clause; 37k is the pre/post-split hard threshold; 32k remains aspirational only).

- [ ] 0.2 Commit spec edit: `docs(spec): adjust FR4 target 32k→37k per TR5 advisory`.

### Phase 1: Mechanism (combined allowlist infra + amendments + compound sync)

TDD order per `cq-write-failing-tests-before`.

#### 1.1 RED — failing tests

Extend `tests/scripts/test_lint_rule_ids.py` with 3 new methods:

```text
test_retired_id_passes_when_in_allowlist
  Seed temp repo with AGENTS.md containing hr-rule-one + hr-rule-two.
  Remove hr-rule-two from working copy.
  Write retired-rule-ids.txt with `hr-rule-two | 2026-04-23 | #2865 | -`.
  Invoke linter with --retired-file <tmp-path>.
  Assert exit 0.

test_missing_retired_file_backward_compat
  No retired-rule-ids.txt present (flag not passed).
  Seed fresh AGENTS.md; no prior commit.
  Assert linter behaves identically to pre-change: exit 0 on valid,
  exit 1 on duplicate/missing-id/invalid-format.

test_reintroduced_retired_id_fails
  retired-rule-ids.txt contains `hr-rule-two | 2026-04-23 | #2865 | -`.
  AGENTS.md contains hr-rule-two as an active rule.
  Invoke linter with --retired-file <tmp-path>.
  Assert exit 1 with 'reintroduced' or 'retired' in stderr.
```

All 3 use existing `_run()` pattern + `tempfile.TemporaryDirectory()`. Pass `--retired-file` via an updated `_run()` signature or a new helper `_run_with_retired(agents_content, retired_content)`.

Commit as `test(lint-rule-ids): RED for retired-ids allowlist`.

#### 1.2 GREEN — linter amendment

Amend `scripts/lint-rule-ids.py`. Minimal addition (~15 lines):

```python
# Add argparse (or sys.argv split) for --retired-file flag:
#   python lint-rule-ids.py [--retired-file <path>] [AGENTS.md ...]
# Path comes from CLI — never inferred from AGENTS.md location.

retired_ids = set()
if retired_file and Path(retired_file).exists():
    for line in Path(retired_file).read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Parse: <id> | <date> | <pr> | <breadcrumb>
        parts = [p.strip() for p in stripped.split("|", 3)]
        if len(parts) >= 1 and parts[0]:
            retired_ids.add(parts[0])

# Inside lint(), after existing head_ids/current_ids computation:
current_ids = set(rid for rid, _ in ids_seen)
reintroduced = retired_ids & current_ids
if reintroduced:
    errors.append(
        f"{path}: retired id(s) reintroduced as active rules: "
        f"{sorted(reintroduced)}. Retired ids may not be reused."
    )
removed = head_ids - current_ids - retired_ids
if removed:
    errors.append(
        f"{path}: removed id(s) detected: {sorted(removed)}. "
        "Add to scripts/retired-rule-ids.txt to retire."
    )
```

**Dropped vs initial plan** (per code-simplicity review): no RETIRED_LINE_RE, no date validation, no ID-format validation for allowlist entries, no malformed-entry listing. Human editors in PR review catch these; overvalidation of an append-only file is gold-plating.

**Path resolution fix** (per Kieran review): `--retired-file` flag replaces the `path.parent / "scripts"` inference that would have broken the existing `_run()` test pattern.

Run `python3 -m unittest tests.scripts.test_lint_rule_ids` — 5 existing + 3 new = 8 tests pass.

Commit: `fix(lint-rule-ids): GREEN — parse retired-ids allowlist via --retired-file`.

#### 1.3 Create `scripts/retired-rule-ids.txt` (empty with header)

```text
# Retired AGENTS.md rule IDs.
#
# Format: <rule-id> | <YYYY-MM-DD> | <PR #NNNN or -> | <breadcrumb>
# - breadcrumb: learning file path, replacement rule id, or "-" (self-contained).
#
# Retired IDs cannot be reintroduced as active rules (enforced by
# scripts/lint-rule-ids.py). Appending a rule id here in the same PR
# that deletes the rule from AGENTS.md is required per cq-rule-ids-are-immutable.
```

Entries appended during Phase 2.

#### 1.4 Amend 3 AGENTS.md rules

**`cq-agents-md-why-single-line`** (current 557 bytes):

> `AGENTS.md rules cap at ~600 bytes each; **Why:** annotations must be one sentence pointing to a PR # or learning file [id: cq-agents-md-why-single-line] [skill-enforced: compound step 8]. AGENTS.md loads every turn; the 40k Claude Code warn is a proxy for the 10-22% per-turn token overhead (see 2026-02-25 learning). Target ≤37,000 bytes; compound step 8 warns above 37k, hard warn at 40k. Rule count is advisory. <!-- rule-threshold: 115 --> **Why:** #2865 — bytes-first policy; #2686 prior.`

(Target ≤600 bytes; preserves existing sentinel since sync-script unchanged.)

**`wg-every-session-error-must-produce-either`** (current 411 bytes):

> `Every session error MUST produce an AGENTS.md rule, skill instruction edit, hook, or learning-file entry [id: wg-every-session-error-must-produce-either]. **Discoverability exit:** if the agent discovers the constraint via a clear error, visible diff, or command failure on first attempt, a learning file alone is sufficient — do NOT add an AGENTS.md rule. Rules only for hidden constraints: silent-failure modes, tool quirks not in docs, invariants surfacing only post-merge, or blast-radius incidents. **Why:** #2865 — 4.7 rules/day inflow consumed 100→115 raise in 2 days.`

**`cq-rule-ids-are-immutable`** (current 285 bytes):

> `Rule IDs on AGENTS.md rules are immutable once assigned [id: cq-rule-ids-are-immutable] [hook-enforced: lint-rule-ids.py]. Rewording preserves the ID; removal requires appending the ID to scripts/retired-rule-ids.txt with retirement date, PR, and breadcrumb. Reintroducing a retired ID is linter-rejected. Section prefixes (hr, wg, cq, rf, pdr, cm) must match the section.`

#### 1.5 Update compound/SKILL.md step 8

Replace current warn message (line ~206):

```markdown
- If `B > 37000`: `"[WARNING] AGENTS.md byte budget (B/37000) exceeded — apply discoverability litmus (wg-every-session-error-must-produce-either) before adding any new rule; consider retiring via scripts/retired-rule-ids.txt."`
- If `B > 40000`: `"[CRITICAL] AGENTS.md exceeds Claude Code 40k warn — harness performance degradation."`
- If `A > 115`: `"[WARNING] rule count advisory (A/115) — focus on bytes; see cq-agents-md-why-single-line."` <!-- rule-threshold: 115 -->
```

Rule-count sentinel preserved (sync script extracts it from both files; plan does NOT add a second sentinel).

#### 1.6 Run verification

- [ ] `python3 -m unittest tests.scripts.test_lint_rule_ids` — 8/8 pass.
- [ ] `bash scripts/lint-agents-compound-sync.sh` — green (`rule-threshold: 115` matches in both files).
- [ ] `wc -c AGENTS.md` — measure new baseline (should be 40,654 + ~300–400 from amendment adds = ~41,000; expected to exceed 40k temporarily until Phase 2 delete pass).

Commit: `docs(agents-md): amend threshold + inflow-litmus + immutability rules; compound byte-threshold to 37k`.

### Phase 2: Delete pass

Judgment-heavy. Work-phase executor applies the litmus per-rule; plan provides **procedure** and **pre-sample** (informational).

#### 2.1 Litmus procedure

For each of 113 rules, top-to-bottom:

1. Read rule text + `**Why:**` annotation.
2. **Primary question:** Can an agent discover this constraint via a clear error, visible diff, or command failure on first attempt?
    - YES → delete candidate (step 4).
    - NO → keep (step 5).
    - AMBIGUOUS → tiebreaker (step 3).
3. **Tiebreaker:** Is there a blast-radius class (silent failure, data loss, force-push recovery, production drift, cross-session retry waste)?
    - YES → keep.
    - NO → keep (TR5 conservative bias).
4. **Delete path:** append to `scripts/retired-rule-ids.txt` with breadcrumb; delete the `- ...` line from AGENTS.md.
5. **Keep path:** no action.
6. **Pointer re-evaluation** (only for rules tagged `[hook-enforced: ...]` or `[skill-enforced: ...]`):
    - Hook/skill ALWAYS invoked in its relevant context? → delete pointer via retired-rule-ids.txt.
    - CONDITIONAL? → keep pointer.

#### 2.2 Pre-sample candidates (reviewer-corrected)

Rules flagged by plan-time litmus application. Work-phase MAY re-judge.

**Delete candidates (13 rules, ~3,552 bytes):**

| ID | Bytes | Rationale |
|---|---|---|
| `hr-before-running-git-commands-on-a` | 213 | `git` errors clearly on non-repo paths. |
| `hr-never-use-sleep-2-seconds-in-foreground` | 381 | Tool blocks with clear message. |
| `cq-always-run-npx-markdownlint-cli2-fix-on` | 204 | markdownlint prints violations. |
| `cq-ensure-dependencies-are-installed-at-the` | 216 | Install/test errors surface missing deps. |
| `cq-gh-issue-create-milestone-takes-title` | 379 | `gh` rejects invalid milestone forms. |
| `cq-gh-issue-label-verify-name` | 371 | `gh` rejects invalid labels. |
| `cq-vite-test-files-esm-only` | 280 | Vite throws `Failed to resolve import`. |
| `cq-markdownlint-fix-target-specific-paths` | 392 | Blast-radius visible in `git status` pre-commit. |
| `cq-when-running-terraform-commands-locally` | 285 | Env-var errors surface in terraform output. |
| `cq-for-production-debugging-use` | 266 | Redundant with Doppler tool availability. |
| `wg-use-ship-to-automate-the-full-commit` | 144 | `/ship` is skill-documented. |
| `rf-never-skip-qa-review-before-merging` | 158 | `/ship` enforces QA/review as skill gates. |
| `rf-after-merging-read-files-from-the-merged` | 163 | Stale reads surface as wrong file content. |

**Explicitly KEPT (reviewer-corrected from earlier draft):**

- `hr-mcp-tools-playwright-etc-resolve-paths` — Playwright errors surface as "element not found" or silent 404 screenshots, not "wrong cwd." Not cleanly discoverable.
- `hr-always-read-a-file-before-editing-it` — rule covers the post-compaction invariant which is NOT discoverable from one error.
- `hr-the-bash-tool-runs-in-a-non-interactive` — agent will retry `sudo`/`su`/`doas` across sessions; rule prevents cross-session waste (blast-radius class).

**Pointer deletes (3 rules, ~624 bytes):**

| ID | Bytes | Hook/skill always-invoked? |
|---|---|---|
| `cq-after-completing-a-playwright-task-call` | 204 | `browser-cleanup-hook.sh` fires on every Playwright close. |
| `cq-before-calling-mcp-pencil-open-document` | 213 | `pencil-open-guard.sh` fires on every Pencil open. |
| `wg-when-a-research-sprint-produces` | 207 | Work skill Phase 2.5 fires every research sprint. |

#### 2.3 Execute delete pass

- [ ] 2.3.1 For each candidate, apply litmus per 2.1 and record decision.
- [ ] 2.3.2 Append retired IDs to `scripts/retired-rule-ids.txt` with breadcrumbs (learning file path where available, else one-line self-contained text).
- [ ] 2.3.3 Delete retired `- ...` lines from AGENTS.md.
- [ ] 2.3.4 `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md` — green.
- [ ] 2.3.5 `wc -c AGENTS.md` — must be < 37,000. If ≥ 37,000, identify additional candidates or flag as blocker.
- [ ] 2.3.6 Commit: `chore(agents-md): delete N rules via discoverability litmus; retire via allowlist`.

#### 2.4 Build PR body audit table

Touched-rules-only. Format:

```markdown
## Per-rule decisions (touched only)

| rule-id | action | rationale | breadcrumb |
|---|---|---|---|
| hr-before-running-git-commands-on-a | deleted | LITMUS: git errors clearly on non-repo | — (one-line) |
| cq-after-completing-a-playwright-task-call | deleted (pointer) | always-invoked hook | `plugins/soleur/hooks/browser-cleanup-hook.sh` |
| ... 14 more rows ... |
```

Untouched rules (~97) are NOT rowed. Reviewers trust the KEEP decisions without per-row justification.

### Phase 3: Ship

- [ ] 3.1 Update PR body with the Phase 2.4 decision table.
- [ ] 3.2 `npx markdownlint-cli2 --fix AGENTS.md knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md knowledge-base/project/specs/feat-agents-md-shrink/spec.md knowledge-base/project/plans/2026-04-23-chore-agents-md-shrink-via-allowlist-plan.md`.
- [ ] 3.3 `bash scripts/lint-agents-compound-sync.sh` — green.
- [ ] 3.4 `python3 -m unittest tests.scripts.test_lint_rule_ids` — 8/8 green.
- [ ] 3.5 `wc -c AGENTS.md` < 37,000 (final verification).
- [ ] 3.6 `/ship` — review agents + compound + PR ready.
- [ ] 3.7 Post-merge: fresh Claude Code session → verify warn does NOT fire.

## Alternative Approaches Considered

| Approach | Chosen? | Rationale |
|---|---|---|
| **A** (3 sequential PRs: allowlist → telemetry → delete) | No | Telemetry non-blocking. |
| **B** (2 bundled PRs) | No | Telemetry doesn't help existing rules. |
| **C** (mega-PR with telemetry) | No | Conflates mechanism with policy; unreviewable. |
| **D** (single PR: allowlist + inflow rule + delete; defer telemetry) | **Yes** | Fastest to 37k. |
| **DHH-minimal** (no allowlist; just delete, handle reintroduction when it happens) | No | Each delete violates `cq-rule-ids-are-immutable` without allowlist mechanism. |

## Non-Goals (deferred with tracking)

- **Telemetry fix** — tracked in #2866 (explicit non-goal per spec FR5).
- **Longest-rule compression** — `hr-never-fake-git-author` (756 bytes) tracked in #2867.

Constitution.md audit and aggressive rule consolidation are NOT tracked — they are out of scope without concrete trigger.

## Risks & Mitigations

| Risk | Probability | Mitigation |
|---|---|---|
| Delete pass over-shrinks a load-bearing rule | Medium | TR5 bias toward KEEP; per-rule PR audit trail; reviewer challenge. |
| 4.7 rules/day inflow refills budget in ~5 weeks | High next cycle | Litmus amendment (1.4); compound step 8 applies at promotion. |
| Retired ID reintroduced by future compound | Low | Linter rejects; test coverage in 1.1. |
| Byte-margin at 37k target is tight (~120-320 bytes) | Medium | Re-measure gate after Phase 1; adjust Phase 2 candidates if margin < 200. |
| Amendments add more bytes than the ~300-400 projection | Medium | Measure post-Phase 1; drop the widest accepted delete if margin tight. |
| Spec↔plan divergence (32k vs 37k) surfaces at `/ship` gate | Low | Phase 0 edits spec FR4 inline. |

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm).

Brainstorm `## Domain Assessments` flagged engineering-only (tooling governance, internal agent harness). No marketing, legal, operations, product, sales, finance, or support implications. No user-facing changes. No new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files — Product/UX Gate mechanical escalation = NONE.

spec-flow-analyzer not invoked — mechanical phases covered by `tests/scripts/test_lint_rule_ids.py`; judgment phase guarded by the litmus procedure + per-rule audit trail.

## References

- #2865 (primary), #2762 (Closes), #2866 (telemetry), #2867 (longest-rule)
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-agents-md-shrink/spec.md`
- Measurement learning: `knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md`
- Prior learnings: `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`, `2026-04-18-agents-md-byte-budget-and-why-compression.md`, `2026-02-25-lean-agents-md-gotchas-only.md`
- Prior PR: #2754 (+21 bytes net pointer migration)
- Files: `scripts/lint-rule-ids.py`, `scripts/lint-agents-compound-sync.sh`, `tests/scripts/test_lint_rule_ids.py`, `plugins/soleur/skills/compound/SKILL.md` line 205, `AGENTS.md` line 78
