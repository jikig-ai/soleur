---
issue: 3684
branch: feat-one-shot-3684-agents-md-pre-commit-rule-budget
lane: single-domain
requires_cpo_signoff: false
type: chore
---

# chore(agents): pre-commit hook for AGENTS.md rule-budget + skill-enforced-anchor parity

Closes #3684

## Overview

Two silent-drift surfaces around the AGENTS.md registry are not commit-gated today:

1. **Always-loaded byte budget.** `B_ALWAYS = wc -c AGENTS.md + wc -c AGENTS.core.md` is the harness performance ceiling (22 k). Compound rule-budget step 8 surfaces breaches advisorily at `/compound` time but does not block commits. PR #3681 trimmed B_ALWAYS to 21,985 B (15 B headroom under 22 k). At the documented 4.7-rules/day growth-rate (~700 B/day) the budget will re-trip within 1-13 days post-merge unless a commit-blocking gate exists.
2. **Per-rule byte cap.** `cq-agents-md-why-single-line` caps each rule body at ~600 B. Currently advisory only (compound step 8 warns; `lefthook` does not reject).
3. **Skill-enforced anchor parity.** `lint-agents-enforcement-tags.py` verifies that the `<skill>` slug in `[skill-enforced: <skill> <anchor>]` resolves to a real `plugins/soleur/skills/<skill>/SKILL.md` file but explicitly does NOT verify the `<anchor>` token (phase/step/heading reference). Pattern-recognition F6 in PR #3681 surfaced this gap. **Pre-plan parity sweep already finds drift** — see Research Reconciliation below: `[skill-enforced: plan Phase 1.4, deepen-plan Phase 4.5]` does not substring-match `plan/SKILL.md` (the heading is `### 1.4. Network-Outage Hypothesis Check`, not `Phase 1.4`); `[skill-enforced: compound Route-Learning-to-Definition]` does not match because compound's heading is space-separated (`### Route Learning to Definition`), not hyphenated. The new gate must therefore EITHER tolerate the two heading styles OR the existing tags must be normalized to match SKILL.md prose in the same PR.

The fix lands as a new dedicated linter `scripts/lint-agents-rule-budget.py` (byte-budget assertions, commit-blocking) plus an extension to `scripts/lint-agents-enforcement-tags.py` (anchor-parity check, commit-blocking, with tolerant matching). Both wire into `lefthook.yml` pre-commit on AGENTS*.md staged-file changes. No CI mirror — the existing AGENTS linters all rely on lefthook pre-commit, which is the canonical first-line gate.

## User-Brand Impact

**If this lands broken, the user experiences:** the pre-commit hook rejects a legitimate AGENTS.md edit (false positive on the per-rule cap or anchor parity), blocking unrelated work until the operator bypasses with `--no-verify`. Worst-case operator workaround drift: `--no-verify` becomes habitual and the gate stops protecting anything.

**If this leaks:** N/A — pure tooling change. No regulated data, no auth, no schema, no operator-facing artifact distribution.

**Brand-survival threshold:** none, reason: AGENTS.md tooling change; the budget gate protects a performance ceiling (harness perf), not user data.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "Pattern-recognition F6 in PR #3681 noted there is no parity test asserting that every `[skill-enforced: <skill> <anchor>]` tag in AGENTS.core.md resolves to a real anchor in the named skill file." | Confirmed: `scripts/lint-agents-enforcement-tags.py:127-135` parses the `<skill>` slug via `SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([a-z][a-z0-9-]*)([^\]]*)\]")` and only asserts `SKILL.md` file existence. The trailing `([^\]]*)` captures the anchor but is unused. | Extend the existing script (do not create a third). Use a tolerant matcher that normalizes the two known heading styles (see TR3). |
| "Compound rule-budget step 8 surfaces budget breaches advisorily at commit time but does NOT block commit on `[CRITICAL]`." | Confirmed: `plugins/soleur/skills/compound/SKILL.md:218-230` prints warnings but is invoked by `/compound`, not by `lefthook`. Lefthook today runs `rule-id-lint`, `agents-compound-sync`, `agents-enforcement-tag-lint` against AGENTS*.md — no byte-budget check. | New script `scripts/lint-agents-rule-budget.py` wired into `lefthook.yml`. Compound step 8 remains advisory (informational only) and points at the new linter for hard enforcement. |
| "PR #3681 added 466 B then 15 B of headroom under 22 k." | Measured at plan time: `wc -c AGENTS.md AGENTS.core.md` → 4,602 + 17,383 = 21,985 B → 22,000 - 21,985 = **15 B headroom**. 74 rules total; longest rule body = 582 B (under 600 B cap). | AC measures B_ALWAYS at plan time and ship time; expects no headroom regression. Linter ships with current 21,985 B passing under both 20 k WARN and 22 k REJECT (only WARN should fire — see TR1 threshold table). |
| "For each `[skill-enforced: <skill> <bullet-title>]` tag … assert `grep -F '<bullet-title>'` in SKILL.md." | Pre-plan parity sweep against current AGENTS.core.md found two dangling anchors under literal `grep -F` semantics: `Phase 1.4` (not in `plan/SKILL.md` — heading is `### 1.4. Network-Outage Hypothesis Check`); `Route-Learning-to-Definition` (compound's heading is `### Route Learning to Definition`, no hyphens). | Tolerant matcher (TR3): `Phase X.Y` ↔ heading `### X.Y` and hyphen↔space normalization. Both tags pass under the tolerant matcher; no AGENTS.md edits required. |
| "lefthook or `.claude/hooks/`" (issue ambiguity) | `.claude/hooks/` are SessionStart hooks (not commit-time). The repo's commit-time gates all live in `lefthook.yml` under `pre-commit:`. | Lefthook only. `.claude/hooks/` is the wrong wire-up surface — they are CC-session hooks, not git-commit hooks. |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for p in scripts/lint-rule-ids.py scripts/lint-agents-enforcement-tags.py lefthook.yml AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md plugins/soleur/skills/compound/SKILL.md; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title) (path: \($path))"' /tmp/open-review-issues.json
done
```

None. No open `code-review`-labelled issues reference the files this plan edits.

## Functional Requirements

- **FR1.** A new pre-commit linter `scripts/lint-agents-rule-budget.py` MUST reject `git commit` when, after applying the staged diff, `wc -c AGENTS.md + wc -c AGENTS.core.md > 22000`.
- **FR2.** The same linter MUST warn (non-blocking) when the post-stage `B_ALWAYS ≥ 20000` AND `≤ 22000`. Warn prints to stderr but exit code is 0.
- **FR3.** The same linter MUST reject `git commit` when any rule body line (`^- ` inside a `## <SECTION>` whose name is in the canonical `SECTIONS` set used by `lint-rule-ids.py`) exceeds 600 bytes in any of AGENTS.{md,core.md,docs.md,rest.md}.
- **FR4.** `scripts/lint-agents-enforcement-tags.py` MUST be extended to validate every `[skill-enforced: <skill> <anchor>...]` pair (comma-separated) by asserting that the anchor token resolves to a substring of `plugins/soleur/skills/<skill>/SKILL.md` under the tolerant matcher specified in TR3.
- **FR5.** Both linters MUST wire into `lefthook.yml` `pre-commit:` under the same `glob:` set already used by `rule-id-lint` and `agents-enforcement-tag-lint` (AGENTS.{md,core.md,docs.md,rest.md}). The byte-budget linter MUST also fire on edits to `scripts/lint-agents-rule-budget.py` itself (linter self-test convention used by `lint-scheduled-show-full-output`).
- **FR6.** Both linters MUST exit 0 against the current `main` working tree at the moment this PR is opened. Pre-existing parity drift (Research Reconciliation row 4) is resolved by the tolerant matcher, not by editing AGENTS.core.md.
- **FR7.** Compound rule-budget step 8 in `plugins/soleur/skills/compound/SKILL.md` MUST be updated to (a) keep the advisory output but (b) cross-reference the new commit-blocking linter so operators know the gate's authoritative location. No threshold semantic change to compound itself.

## Technical Requirements

- **TR1. Threshold table.**

  | Surface | Warn (stderr, exit 0) | Reject (stderr, exit 1) |
  |---|---|---|
  | `B_ALWAYS` (always-loaded) | ≥ 20000 B | > 22000 B |
  | Per-rule body | (none — drop the warn tier; one-tier reject keeps the linter simple) | > 600 B |
  | Skill-enforced anchor parity | (none) | unresolved anchor under TR3 matcher |

  The compound step 8 advisory at 18 k (and its 115-rule advisory) MUST be preserved unchanged — those tiers serve a different audience (the `/compound` operator deciding whether to retire a rule). The pre-commit gate uses the harder 20 k/22 k spec from the issue body to keep the gate cheap and predictable.

- **TR2. Per-rule body extraction MUST mirror `lint-rule-ids.py:80-91`** — only count lines that (a) live under a `## <heading>` whose stripped value is in `SECTIONS = {"Hard Rules","Workflow Gates","Code Quality","Review & Feedback","Passive Domain Routing","Communication","Compliance Tier"}`, and (b) begin with `^- `. The pointer index lines in AGENTS.md (e.g. `- [id: hr-x] → core`) are short by construction; no special case needed. The byte unit is the line's UTF-8 byte length INCLUDING the leading `- ` and trailing newline-excluded (i.e. `len(line.encode("utf-8"))`), matching the compound step 8 `awk '{print length}'` semantic.

- **TR3. Anchor-parity tolerant matcher.** For each pair `(skill, anchor)` extracted from a `[skill-enforced: <skill> <anchor1>, <skill2> <anchor2>, ...]` tag:
  1. Read `plugins/soleur/skills/<skill>/SKILL.md` once and cache its content.
  2. Try literal `anchor in content` (substring match — the `grep -F` semantic the issue body prescribes).
  3. If literal fails, apply normalization variants in order and try each:
     - Replace any `Phase\s+(\d+(?:\.\d+)*)` with `### \1` and try again (matches `Phase 1.4` ↔ `### 1.4. Network-Outage Hypothesis Check`).
     - Replace any `step\s+(\d+)` (case-insensitive on "step") with `## Phase 1.5: …` then with `step \1` literal in body prose (compound step 8 is referenced as `step 8` in tag, appears as both `## Phase 1.5` and prose `step 8` — the prose match wins).
     - Replace hyphens-in-anchor with spaces and try `<spaced-anchor> in content` (matches `Route-Learning-to-Definition` ↔ `Route Learning to Definition`).
  4. Anchors that look like agent names (contains a hyphen AND no digit, AND `plugins/soleur/agents/**/<anchor>.md` exists) resolve via the agent-file existence check INSTEAD of substring-in-SKILL.md (matches `user-impact-reviewer`).
  5. If all variants fail, emit a hard error `{agents_file}:{line}: ERROR: [skill-enforced: {skill} {anchor}] — anchor not resolvable in plugins/soleur/skills/{skill}/SKILL.md under any tolerant variant. Fix: align the tag wording to the SKILL.md heading, or update the heading.`

- **TR4. Comma-split parser.** The current `SKILL_TAG_RE` captures `(skill, rest)` as two groups; `rest` may be `" Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6"`. Split `rest` on `,` and re-parse each fragment as `^\s*([a-z][a-z0-9-]*)\s+(.+?)\s*$` to recover subsequent `(skill, anchor)` pairs. The first pair uses the regex's first capture; pairs 2+N come from the comma-split.

- **TR5. Sentinel behavior on missing AGENTS sidecars.** If `AGENTS.core.md` is staged for deletion (or absent on disk), the byte-budget linter MUST exit 2 with `ERROR: AGENTS.core.md missing — refusing to compute B_ALWAYS`. This matches `lint-rule-ids.py`'s exit-2-on-missing-file convention.

- **TR6. UTF-8 handling.** `wc -c` returns bytes (not chars). The Python linter MUST use `len(path.read_bytes())` not `len(path.read_text())` to match. Equivalent on ASCII; differs on multi-byte glyphs that have crept into rule bodies (the rules currently use plain ASCII + the `→` arrow — `→` is 3 bytes UTF-8).

- **TR7. `--check-staged` flag for symmetry with lefthook's `{staged_files}`.** The linter accepts positional file args. Lefthook will pass the staged AGENTS*.md path set. The linter computes B_ALWAYS from the SET of staged files INTERSECTED with the always-loaded set `{AGENTS.md, AGENTS.core.md}`; for files NOT in the staged set but in the always-loaded set, it reads from disk. This mirrors lefthook's intent: the gate fires on each commit and the inputs are the post-stage state of the always-loaded pair.

- **TR8. Test harness convention.** Add `scripts/lint-agents-rule-budget.test.sh` following `scripts/compound-promote.test.sh` shape: `mktemp -d` per case, point the linter at a synthesized fixture pair, assert exit code + stderr substring. Add equivalent additional cases to a new `scripts/lint-agents-enforcement-tags.test.sh` (the existing script has no test file — this PR adds one).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `scripts/lint-agents-rule-budget.py` exists, is executable, and exits 0 against the current `main` working tree. Verify: `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"` → `exit=0`.
- [ ] **AC2.** Byte-budget WARN fires at B_ALWAYS ≥ 20000 (current value 21,985). Verify by running the linter against the live files — should print `[WARN] B_ALWAYS=21985 ≥ 20000 (warn tier)` to stderr and still exit 0.
- [ ] **AC3.** Byte-budget REJECT fires above 22000. Verify via synthesized fixture: copy AGENTS.core.md, append a 100-byte filler rule (total 22,083), run linter against the fixture pair, assert exit 1 + stderr substring `B_ALWAYS=22083 > 22000`.
- [ ] **AC4.** Per-rule REJECT fires above 600 bytes. Verify via synthesized fixture: a single sidecar with one body line of 601 chars under `## Hard Rules`, exit 1 + stderr substring `exceeds 600 B`.
- [ ] **AC5.** `scripts/lint-agents-enforcement-tags.py` extended for anchor parity exits 0 against the current main working tree. Verify: `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"` → `exit=0`. The script's success line MUST mention the parity check count (`OK: all <hook-tags> hook + <skill-tags> skill + <anchor-pairs> anchor parity check(s) resolve`).
- [ ] **AC6.** Anchor-parity REJECT fires when a tag points at a missing anchor. Verify via synthesized fixture: a sidecar containing `[skill-enforced: compound nonexistent-anchor]`, exit 1 + stderr substring `anchor not resolvable`.
- [ ] **AC7.** Tolerant matcher resolves both real-world drift cases (`Phase 1.4` ↔ `### 1.4.`; `Route-Learning-to-Definition` ↔ `Route Learning to Definition`). Verify with a dedicated test row in `scripts/lint-agents-enforcement-tags.test.sh`.
- [ ] **AC8.** `lefthook.yml` registers both linters under `pre-commit:` with the same `glob:` set as `rule-id-lint`. Verify: `bash -c "lefthook run pre-commit --commands rule-budget-lint,enforcement-tag-lint" 2>&1` exits 0 against the current tree (requires lefthook installed; if absent, run the Python scripts directly).
- [ ] **AC9.** Bash sanity-test the rejection path end-to-end: `cd $(mktemp -d) && git init -q && cp -r <worktree>/{AGENTS*.md,scripts,lefthook.yml,plugins} . && git add -A && git commit -m bootstrap --no-verify -q && printf '\n- [id: hr-test-overflow-%s] **Why:** filler\n' "$(head -c 700 /dev/urandom | base64 | tr -d '\n' | head -c 700)" >> AGENTS.core.md && git add AGENTS.core.md && git commit -m fail 2>&1 | grep -E '(exceeds 600 B|B_ALWAYS=.* > 22000)'` — exits non-zero with the expected substring.
- [ ] **AC10.** Compound step 8 in `plugins/soleur/skills/compound/SKILL.md` adds a one-line pointer: `**Commit-gate:** `scripts/lint-agents-rule-budget.py` is the authoritative pre-commit reject; this step 8 output is advisory-only (warns at 18 k; the commit gate rejects at 22 k).` Verify by reading the file.
- [ ] **AC11.** Test scripts `scripts/lint-agents-rule-budget.test.sh` and `scripts/lint-agents-enforcement-tags.test.sh` are executable and exit 0. Verify: `bash scripts/lint-agents-rule-budget.test.sh && bash scripts/lint-agents-enforcement-tags.test.sh`.
- [ ] **AC12.** Existing tag set (10 distinct skill-enforced tags surveyed at plan time) all resolve under the tolerant matcher. Verify: parity linter against current AGENTS sidecars prints `OK: …` for every tag enumerated in the plan body's "Tag inventory" appendix.
- [ ] **AC13.** Add `[hook-enforced: lefthook lint-agents-rule-budget.py]` tag to `cq-agents-md-why-single-line` in `AGENTS.docs.md` (single tag only — per AC16 the second tag would breach the 600 B cap). The companion rule `cq-agents-md-tier-gate` is already implicitly enforced by lefthook's `agents-enforcement-tag-lint` command on the same glob; no tag addition needed. Trim the rule's `**Why:**` clause by ~30 B if necessary to stay under 600 B post-edit. Verify the new tag resolves via `lefthook_command_known` (substring `lint-agents-rule-budget.py` in `lefthook.yml`).
- [ ] **AC14.** Commit message and PR body include `Closes #3684`.
- [ ] **AC16.** Post-edit B_ALWAYS budget. Measure `B_ALWAYS = $(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md)` AND `B_DOCS = $(wc -c < AGENTS.docs.md)` after all AC13 + AC10 edits land. Assert: post-edit `B_ALWAYS ≤ 22000`. Assert: per-rule body sizes for `cq-agents-md-why-single-line` (in AGENTS.docs.md) and `cq-agents-md-tier-gate` (in AGENTS.docs.md) each remain `≤ 600 B` after the tag additions. If either edit pushes its rule past 600 B, the `**Why:**` clause MUST be trimmed in the same edit. Plan-time baseline (measured 2026-05-12): cq-agents-md-why-single-line = 572 B, cq-agents-md-tier-gate = 553 B. Tag addition `[hook-enforced: lefthook lint-agents-rule-budget.py]` ≈ 53 B; the `cq-agents-md-tier-gate` candidate addition `[hook-enforced: lefthook lint-agents-enforcement-tags.py]` ≈ 60 B. Projected post-edit sizes: 625 B (over cap) and 613 B (over cap). **Mitigation:** trim the `**Why:**` clauses by ~30 B each to stay under 600 B. Alternative: add only to the `cq-agents-md-why-single-line` rule (one tag), and rely on the existing `[hook-enforced: lefthook lint-rule-ids.py]` implicit coverage for `cq-agents-md-tier-gate`. Choose the alternative — the existing tag is already implicitly enforced by lefthook on the same glob.

### Post-merge (operator)

- [ ] **AC15.** Open a fresh Claude Code session and confirm `[rules-loader] loaded:` stamp shows `AGENTS.core.md` parsing cleanly. No-op verification (the gates are commit-time, not runtime).

## Files to Edit

- `scripts/lint-agents-enforcement-tags.py` — extend `SKILL_TAG_RE` consumption to validate per-pair anchor parity (TR3, TR4). Update success line per AC5.
- `lefthook.yml` — register `rule-budget-lint` and ensure `agents-enforcement-tag-lint` continues to fire on the new SKILL.md edits referenced by anchors (already covered by the existing `glob:` set; no edit needed unless a new SKILL is touched by AC13 tag additions).
- `plugins/soleur/skills/compound/SKILL.md` — add the one-line commit-gate cross-reference per AC10. NO threshold change. Two lines max.
- `AGENTS.docs.md` — add `[hook-enforced: lefthook lint-agents-rule-budget.py]` tag to `cq-agents-md-why-single-line` ONLY (per AC13 + AC16 the second-tag addition to `cq-agents-md-tier-gate` is dropped to stay under the 600 B per-rule cap). Trim the rule's `**Why:**` clause by ~25 B if the post-edit size exceeds 600 B.
- `knowledge-base/project/specs/feat-one-shot-3684-agents-md-pre-commit-rule-budget/tasks.md` — generated at Save Tasks phase.

## Files to Create

- `scripts/lint-agents-rule-budget.py` — new commit-blocking linter (FR1, FR2, FR3, FR5, FR6, TR1, TR2, TR5, TR6, TR7).
- `scripts/lint-agents-rule-budget.test.sh` — bash test harness (TR8, AC3, AC4, AC9, AC11).
- `scripts/lint-agents-enforcement-tags.test.sh` — bash test harness for parity check (TR8, AC6, AC7, AC11, AC12).

## Implementation Phases

### Phase 0. Plan-time fact-checks (before /work begins)

Already done at plan-write time:
- `wc -c AGENTS.md AGENTS.core.md` → 21,985 B (15 B headroom under 22 k).
- 74 rules total across all sidecars; longest rule body 582 B (under 600 cap).
- Pre-existing tag inventory (10 distinct skill-enforced tags, 5 hook-enforced tags) cataloged below.
- 2 anchor-parity drifts exist under literal `grep -F` (resolved by tolerant matcher, not by AGENTS edits).
- Lefthook is the canonical commit-gate surface; `.claude/hooks/` is wrong (SessionStart hooks).

### Phase 1. Write failing tests (TDD per `cq-write-failing-tests-before`)

Create `scripts/lint-agents-rule-budget.test.sh` and `scripts/lint-agents-enforcement-tags.test.sh` with cases that exercise:
- per-rule body > 600 B → exit 1, stderr matches `exceeds 600 B`
- B_ALWAYS > 22000 → exit 1, stderr matches `B_ALWAYS=.* > 22000`
- B_ALWAYS ≥ 20000 AND ≤ 22000 → exit 0, stderr matches `WARN`
- anchor `Phase 1.4` against a SKILL.md with `### 1.4.` → resolves under tolerant matcher
- anchor `Route-Learning-to-Definition` against `Route Learning to Definition` → resolves
- anchor `nonexistent-anchor` against any SKILL.md → exit 1, stderr matches `anchor not resolvable`
- agent-name anchor (`user-impact-reviewer`) → resolves via agent-file existence check

These tests fail because the new script doesn't exist and the parity check isn't wired yet.

### Phase 2. Implement `scripts/lint-agents-rule-budget.py`

- Argparse: positional file paths (default `AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`).
- Read `B_INDEX = len(open("AGENTS.md","rb").read())` and `B_CORE = len(open("AGENTS.core.md","rb").read())`. Exit 2 if either missing (TR5).
- Compute `B_ALWAYS = B_INDEX + B_CORE`. Print to stderr per TR1.
- Reject (`return 1`) on `B_ALWAYS > 22000`. Warn (return 0) on `B_ALWAYS ≥ 20000`.
- For each AGENTS file passed in, walk lines per TR2 section-aware logic, measure each rule body's UTF-8 byte length, reject on any > 600 B.
- Tests from Phase 1 turn green.

### Phase 3. Extend `scripts/lint-agents-enforcement-tags.py` for anchor parity

- Add `SKILLS_DIR = "plugins/soleur/skills"`, `AGENTS_DIR = "plugins/soleur/agents"`.
- Add `resolve_anchor(skill, anchor, root) -> bool` per TR3 (literal substring → Phase normalization → hyphen↔space normalization → agent-file fallback).
- In the existing `lint()` loop, after the skill-existence check, also iterate over comma-split fragments per TR4 and call `resolve_anchor` for each.
- Update the success message per AC5.
- Tests from Phase 1 turn green.

### Phase 4. Wire into `lefthook.yml`

- Append a new `rule-budget-lint` command under `pre-commit:` mirroring `rule-id-lint`'s `glob:` block (AGENTS*.md + the new linter script self-glob).
- The existing `agents-enforcement-tag-lint` command's `glob:` already covers AGENTS*.md and the existing script — no `glob:` widening needed for Phase 3 changes (the same script is invoked).

### Phase 5. Update compound + AGENTS.docs.md cross-references

- `plugins/soleur/skills/compound/SKILL.md` step 8: add the AC10 one-line pointer.
- `AGENTS.docs.md`: add the AC13 `[hook-enforced: lefthook lint-agents-rule-budget.py]` tag to `cq-agents-md-why-single-line` only (the second tag is dropped per AC16 budget analysis). Measure per-rule byte size after edit; if > 600 B, trim the rule's `**Why:**` clause per `cq-agents-md-why-single-line` until under the cap.

### Phase 6. End-to-end verification

- Run both linters against the current tree (AC1, AC2, AC5, AC12).
- Run both test scripts (AC11).
- Run the AC9 end-to-end rejection script.
- Stage + commit a deliberately-broken AGENTS edit locally (with `--no-verify` to bypass `git commit`'s pre-commit so the lefthook output can be inspected as `lefthook run pre-commit`), confirm the lefthook output shows both linters firing.
- Measure post-edit B_ALWAYS — must still be ≤ 22000.

### Phase 7. Compound + ship

- Run `/soleur:compound` per `wg-before-every-commit-run-compound-skill` before the final commit.
- Run `/soleur:ship` per `hr-before-shipping-ship-phase-5-5-runs`.

## Enhancement Summary (deepen-plan pass, 2026-05-12)

**Deepened on:** 2026-05-12
**Sections enhanced:** Tag inventory (corrected), Risks (R7 added), Sharp Edges (4 new entries), TR3 (anchor-name agent fallback hardened), Acceptance Criteria (AC16 added — measured-headroom assertion).

### Key Improvements

1. **Tag-inventory empirical sweep widened from 2 to 4 anchors requiring tolerant matching.** Initial plan claimed 2 drifts (`plan Phase 1.4`, `compound Route-Learning-to-Definition`). Direct `grep -F` against every SKILL.md surfaced 2 more: `plan Phase 2.6` (heading is `### 2.6. User-Brand Impact Section`, not `Phase 2.6`) and `deepen-plan Phase 4.6` (heading is `### 4.6. User-Brand Impact Halt`, not `Phase 4.6`). The tolerant matcher's `Phase X.Y` → `### X.Y` rule resolves all 4 cleanly. Tag-inventory section below is corrected.
2. **Comma-split parser validated empirically.** The 5-pair tag `[skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6]` was parsed against the regex `^\s*([a-z][a-z0-9-]*)\s+(.+?)\s*$` after `.split(",")` — all 5 pairs extract correctly. TR4 stands.
3. **`wc -c` vs `len(bytes)` semantic confirmed identical** for both current always-loaded files (both 4,602 / 17,383 with trailing `\n`). Sharp Edges entry kept as a guard for future drift.
4. **PR/issue citation reconciled:** Plan originally referenced "PR #3682" — actually issue **#3682** (workflow hardening, OPEN, Ref #3679) and **PR #3688** (which references issue #3682, OPEN). The Overview's reference to "#3682, open in PR #3688" survived intact in the issue body but was not separately cited in the plan. No plan-body correction needed; this is a one-shot context note.
5. **Tolerant matcher false-positive risk re-assessed.** `compound step 8` matches `step 8` as substring. The only other `step N` reference in compound/SKILL.md is the heading itself. False-positive surface is bounded; documented in Sharp Edges.

### New Considerations Discovered

- The plan body's initial Tag inventory was overconfident on literal matching. The corrected inventory below is the authoritative resolution.
- The `Phase X.Y` ↔ `### X.Y` normalization rule (TR3 variant 1) handles 4 of 14 pairs (~29% of the corpus) — it's not a corner case, it's a near-majority pattern. This argues that the tolerant matcher is necessary, not optional.
- Adding `[hook-enforced: lefthook lint-agents-rule-budget.py]` to `cq-agents-md-why-single-line` (AC13) widens that rule's byte size. Measured-headroom assertion (AC16, new) makes the post-edit B_ALWAYS budget check load-bearing in the test plan.

## Tag inventory (resolved at plan time under tolerant matcher)

Hook-enforced tags (5):
- `[hook-enforced: .claude/hooks/ship-unpushed-commits-gate.sh]` — resolves via path-form.
- `[hook-enforced: .github/workflows/secret-scan.yml]` — resolves via path-form.
- `[hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]` — resolves via `scripts/guardrails.sh` (under `HOOK_SEARCH_DIRS`).
- `[hook-enforced: lefthook gdpr-gate.sh]` — resolves via `lefthook_command_known` (substring `gdpr-gate.sh` in `lefthook.yml`).
- `[hook-enforced: lefthook lint-rule-ids.py]` — resolves via same.

Skill-enforced tags (10 distinct):
- `compound step 8` → literal substring `step 8` in `compound/SKILL.md` (line 197 and elsewhere). ✅
- `compound Route-Learning-to-Definition` → tolerant: hyphen↔space → `Route Learning to Definition` (compound/SKILL.md line 334). ✅
- `brainstorm Phase 0.5` → literal substring `Phase 0.5` (brainstorm/SKILL.md). ✅ (sweep showed match)
- `brainstorm Phase 0.1` → literal substring (per same sweep). ✅
- `plan Phase 2.6` → tolerant: `Phase 2\.6` → `### 2.6` (plan/SKILL.md line 358 `### 2.6. User-Brand Impact Section (Always)`). ✅ [corrected at deepen-plan; was wrongly listed as literal]
- `plan Phase 2.7` → literal substring (plan/SKILL.md line 399 `[skill-enforced: gdpr-gate at plan Phase 2.7]`). ✅
- `plan Phase 1.4` → tolerant: `Phase 1\.4` → `### 1.4` (plan/SKILL.md line 121 `### 1.4. Network-Outage Hypothesis Check`). ✅
- `deepen-plan Phase 4.5` → literal substring (deepen-plan/SKILL.md line 300 `### 4.5. Network-Outage Deep-Dive`). ✅
- `deepen-plan Phase 4.6` → tolerant: `Phase 4\.6` → `### 4.6` (deepen-plan/SKILL.md line 322 `### 4.6. User-Brand Impact Halt (Always)`). ✅ [corrected at deepen-plan; was wrongly listed as literal]
- `review user-impact-reviewer` → agent-name fallback: `plugins/soleur/agents/**/user-impact-reviewer.md` exists. ✅
- `preflight Check 4` / `preflight Check 6` → literal substring. ✅
- `ship Phase 5.5` / `Phase 5.5 Retroactive Gate Application` / `Phase 5.5 Review-Findings Exit Gate` / `Phase 7` → literal substring. ✅
- `work Phase 0 Type-widening cross-consumer grep` / `work Phase 0 Write-boundary sentinel sweep` / `work Phase 2 TDD Gate` / `work Phase 2 exit` → literal substring. ✅

All 14 anchor pairs resolve under the tolerant matcher. **AC12** is therefore expected to pass on the unmodified main tree.

## Non-Goals / Out of Scope

- **Retiring or trimming existing rules.** PR #3681 handled this; the budget is at 21,985 B with 15 B headroom. This PR adds enforcement; it does NOT change rule content (except the AC13 tag additions which are <80 B each).
- **CI mirror.** Lefthook is the canonical first-line gate; the existing `rule-id-lint` and `agents-enforcement-tag-lint` have no CI mirror either. Skipping the GH Actions duplication matches repo convention.
- **Compound step 8 threshold revision.** Compound step 8 stays at 18 k advisory + 22 k informational. The new commit-gate at 20 k WARN / 22 k REJECT is a separate authority. Reconciling the two surfaces' thresholds (e.g. unifying at 20 k everywhere) is a future cleanup tracked at re-evaluation time below.
- **Cross-class budget assertions.** The issue scopes to `B_ALWAYS`. Per-class budgets (`AGENTS.docs.md`, `AGENTS.rest.md`) are NOT enforced because they only load conditionally; growth there is cheaper.
- **Heading-anchor strict matching.** The tolerant matcher is intentionally permissive (substring in any position in SKILL.md). A heading-only matcher could be tightened later if drift surfaces — but the issue body explicitly prescribes `grep -F` (substring) semantics.

## Risks

- **R1. Tolerant matcher false negatives.** A future tag like `plan Phase 99.99` would silently resolve if the literal `Phase 99.99` substring appears anywhere in `plan/SKILL.md`. Mitigation: the matcher is purpose-built for the existing 14-tag corpus; a future audit can tighten if a real false-resolve is observed. Acceptable for chore/tooling scope.
- **R2. Per-rule 600 B cap rejects a legitimately long rule mid-PR.** If a hard rule (`hr-*`) requires 700 B to be unambiguous, the operator faces a forced choice: trim the rule (loss of nuance) or `--no-verify` (gate erosion). Mitigation: the cap already exists as policy (`cq-agents-md-why-single-line`); this PR makes it commit-enforced. Recovery path: split the rule into two cooperating rules, or move the **Why:** clause to a learning file (the cited convention).
- **R3. Multi-byte glyph drift.** Rule bodies use `→` (3 bytes UTF-8). `wc -c` and `len(bytes)` agree; `len(str)` would undercount. TR6 nails the byte semantic.
- **R4. lefthook glob silent skip.** Per the lefthook gobwas-glob trap (`2026-03-21-lefthook-gobwas-glob-double-star.md`), bare `**/*` no-ops without explicit subdirs. Mitigation: reuse the exact `glob:` array shape already used by `rule-id-lint` (path-array enumeration); do NOT introduce new glob patterns.
- **R5. Anchor-parity drift surfaces a real-world unresolved tag.** If a tag exists today that the tolerant matcher can't resolve, the new gate rejects every commit on AGENTS sidecars until the tag is fixed. Mitigation: Tag inventory above shows all 14 current pairs resolve. AC1 + AC5 + AC12 verify against the current tree before this PR opens.
- **R6. Demo-rejection bypass via `--no-verify`.** The gate is a soft-fence — operators can bypass it. Mitigation: same as every other lefthook gate; CI does not re-check (out of scope). Operator discipline is the same surface as all existing pre-commit gates.
- **R7. New gate trips immediately at the current 21,985 B WARN tier.** The first commit to any AGENTS sidecar after this PR merges will print a WARN line (`B_ALWAYS=21985 ≥ 20000`). This is intentional and correct — it surfaces the slim headroom every commit until a rule is retired. Mitigation: documented in AC2; the WARN tier exits 0 and does not block. If operator-fatigue from the constant WARN becomes a problem, deferral path is to widen the WARN tier from 20 k → 21 k in a follow-up.
- **R8. The tolerant matcher's `Phase X.Y` → `### X.Y` rule resolves on prose-context too.** `### 1.4. Network-Outage Hypothesis Check` matches `Phase 1.4` via the variant `### 1.4`. So does any future paragraph that happens to contain `### 1.4` literally (e.g., a code block referencing line 1.4 of a config file). Practical risk: near-zero — heading lines are the only realistic source of `### N.N` substrings. Documented in Sharp Edges below.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Per-rule body-line detection MUST use the same `SECTIONS` set as `lint-rule-ids.py`. If a new section heading is added to AGENTS.md without updating the SECTIONS constant in BOTH linters, the new section's rules will be silently exempt from the 600 B cap. **Mitigation:** Extract `SECTIONS` to a single source-of-truth module (`scripts/_agents_md_sections.py`) that both linters import. Listed in Phase 2.
- `wc -c` includes the trailing newline of the final line. `len(bytes)` does NOT add a synthetic newline. On a file that ends without a trailing newline, the two diverge by 0 (no trailing newline) or 1 (trailing newline). Verify by running both on each AGENTS sidecar at AC1 time and aligning the linter's reporting prose with the actual semantic. The 22 k threshold is loose enough to absorb a 1-byte difference; the linter must report whichever semantic it uses and stick to it.
- Anchor `step 8` matches `step 8` AND `step 80`, `step 87`, etc. as substrings. Pad short numeric anchors with a word-boundary in the tolerant matcher OR accept the false-positive risk (in practice, no SKILL.md has `step 80+` numbering). Choose: accept (simpler). Document in the linter docstring.
- `glob` in lefthook's `lint-agents-rule-budget.py` self-glob should include the test script too, so a test-only edit re-runs the linter. Use the exact path array used by `rule-id-lint`.
- AC9's end-to-end rejection script clones the working tree into a `mktemp -d` — ensure the temp dir contains `lefthook.yml` and a valid `.git/` so `lefthook run pre-commit` can execute. If lefthook isn't on the operator's PATH, fall back to invoking the python scripts directly per AC1+AC2+AC3.
- The tolerant matcher's `Phase X.Y` → `### X.Y` normalization will resolve any paragraph that contains `### X.Y` as a substring (e.g., a fenced code block citing line numbers). Near-zero practical risk because `### N.N` only realistically appears as a markdown heading, but a future audit should tighten this if a fabricated anchor is ever silent-resolved.
- The agent-name fallback (TR3 step 4) checks `plugins/soleur/agents/**/<anchor>.md` existence. This admits any agent name as a valid anchor for any skill — i.e., a tag `[skill-enforced: brainstorm user-impact-reviewer]` would pass even if brainstorm/SKILL.md never references that agent. Acceptable looseness because (a) the producer side (`AGENTS.docs.md` `cq-agents-md-tier-gate` placement gate) controls tag authorship, and (b) the alternative — asserting that the skill body invokes the named agent via `Task <agent-name>` — adds substantial parsing complexity for marginal protection. Tighten later if a real false-pass surfaces.
- When extending `lint-agents-enforcement-tags.py`, preserve its current exit-2-on-arg-error convention. The new parity errors are exit 1, matching the existing skill-existence error semantics. Conflating them would break the lefthook command's known exit-1 expectation.

## Test Scenarios

| ID | Scenario | Expected | Gate |
|---|---|---|---|
| T1 | Current tree | Both linters exit 0; WARN tier fires (B_ALWAYS=21985 ≥ 20000) | AC1, AC2 |
| T2 | AGENTS.core.md grown to 22,083 B | Reject linter exits 1 with `B_ALWAYS=22083 > 22000` | AC3 |
| T3 | One rule line at 601 B | Reject linter exits 1 with `exceeds 600 B` | AC4 |
| T4 | Tag `[skill-enforced: plan Phase 1.4]` against current plan/SKILL.md | Parity linter exits 0 (tolerant: matches `### 1.4.`) | AC7, AC12 |
| T5 | Tag `[skill-enforced: compound Route-Learning-to-Definition]` | Parity linter exits 0 (tolerant: hyphen↔space → matches `Route Learning to Definition`) | AC7, AC12 |
| T6 | Tag `[skill-enforced: compound nonexistent-anchor]` | Parity linter exits 1 with `anchor not resolvable` | AC6 |
| T7 | Tag `[skill-enforced: review user-impact-reviewer]` | Parity linter exits 0 (agent-file fallback: `agents/**/user-impact-reviewer.md` exists) | AC12 |
| T8 | AGENTS.core.md missing on disk | Budget linter exits 2 with `AGENTS.core.md missing` | TR5 |
| T9 | AC9 end-to-end commit-attempt rejection | `git commit` exits non-zero; lefthook output names both linters | AC9 |
| T10 | AC13 tag additions in AGENTS.docs.md | Existing `agents-enforcement-tag-lint` resolves the new hook-enforced tags via lefthook_command_known | AC13 |

## Domain Review

**Domains relevant:** Engineering (tooling).

### Engineering (CTO)

**Status:** reviewed (inline assessment — single-domain tooling change; spawning the CTO domain leader for a chore/tooling change adds ceremony without unlocking new information given the codebase's existing well-trodden lint-script pattern).

**Assessment:** The proposed design mirrors the existing `scripts/lint-rule-ids.py` + `scripts/lint-agents-enforcement-tags.py` shape exactly (Python, argparse, exit 0/1/2 conventions, bash test harness, lefthook `pre-commit:` wire-up with path-array `glob:`). No new dependencies, no new test framework, no new runtime surface. Risk: low. The single load-bearing design choice is the tolerant matcher (TR3) — its correctness is verified by AC7 + AC12 against the current 14-tag corpus.

**Brainstorm-recommended specialists:** None — no brainstorm document exists for this issue (it's a follow-up from PR #3681).

No Product/UX implications. No GDPR surface (TR-only tooling). Skipping the gdpr-gate, ux-design-lead, copywriter, and spec-flow-analyzer specialists.

## Re-evaluation criteria

- If a new AGENTS sidecar section heading is added, audit whether the SECTIONS constant in both linters needs an update (Sharp Edges, Phase 2).
- If the compound step 8 advisory thresholds (18 k WARN / 22 k CRITICAL) ever drift from the commit-gate thresholds (20 k WARN / 22 k REJECT), reconcile in a follow-up — the divergence is intentional today but could confuse a future operator.
- If a `[skill-enforced: ...]` tag is added that the tolerant matcher cannot resolve, either tighten the matcher or relax the tag.

---

*Plan author: Claude Code | Branch: `feat-one-shot-3684-agents-md-pre-commit-rule-budget` | Worktree: `.worktrees/feat-one-shot-3684-agents-md-pre-commit-rule-budget/`*
