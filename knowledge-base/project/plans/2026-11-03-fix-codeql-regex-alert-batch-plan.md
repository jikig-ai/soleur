---
title: "fix: resolve three regex-family CodeQL alerts (222, 245, 300) in one batch"
type: fix
date: 2026-11-03
slug: fix-codeql-regex-alert-batch
branch: feat-one-shot-codeql-regex-alert-batch
issue: 9550
closes: 9550
lane: cross-domain
---

# fix: resolve three regex-family CodeQL alerts (222, 245, 300) in one batch

## Overview

Three open code-scanning alerts share one defect family — regexes whose
character ranges or anchors are wider/looser than intended. All three are
real defect surfaces (or deliberate-fixture shapes CodeQL cannot
distinguish from one); each gets a minimal, semantics-preserving fix in a
single PR. `lane:` defaulted to cross-domain (no spec.md carries one —
fail-closed per plan convention).

## User-Brand Impact

- **If this lands broken, the user experiences:** a CI lint gate
  (`lint-anthropic-content-position`, the affected-replay ratchet, or the
  no-network-fonts sweep) that either rejects valid work or silently
  passes a violation it exists to catch.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no user-data vector — the touched files are repo-internal CI guards and
  one test suite.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** regex changes in CI guards and a
  test fixture are verified by dedicated suites pre-merge; no user-facing
  artifact changes.

*Scope-out override:* `threshold: none, reason: the diff touches only repo-internal guard scripts and a test file — no user-facing, data, or credential surface`

## Research Insights

### Premise Validation (Phase 0.6)

- `gh api repos/jikig-ai/soleur/code-scanning/alerts/{222,245,300}`: all
  three `state: open`, `dismissed_reason: null`, on `refs/heads/main` at
  commit `aa2e3aed00` — the same SHA this worktree branched from. Premise
  holds.
- `#N` in the ask are **CodeQL alert numbers**, not GitHub issues — GitHub
  issue #222 (closed by PR #224), PR #245, PR #300 are unrelated artifacts
  with coincidental numbers. The real tracker is **#9550**
  (`sec: CodeQL alert #245 — js/regex/missing-regexp-anchor`, OPEN,
  `priority/p1-high`, `action-required`, `type/security`).
- Collision pre-check `collision-precheck.sh 9550`: `prs=none`, two
  foreign `test-all.sh` processes in unrelated worktrees
  (`feat-local-test-gate-speed`, `feat-one-shot-12027-commit-author-identity-gate`)
  — capacity contention only, no same-defect sibling. Sibling worktree
  `feat-one-shot-codeql-dedupe-fix` (PR #12000, open) touches
  `.github/workflows/codeql-to-issues.yml` — same subsystem name,
  disjoint scope and file set.
- Alert-location resolution: alert #222 points at
  `scripts/lint-anthropic-content-position.py` line 33 cols 181-184, which
  resolves inside the `re.VERBOSE` literal to the range `h-1` inside the
  trailing comment `[x.y.length-1]` — i.e. CodeQL is parsing VERBOSE-mode
  comment text as pattern characters. Message: "Suspicious character
  range that is empty."

### Property List (Phase 0.6b)

1. Alert #222's flagged text (`h-1` inside a VERBOSE comment) no longer
   parses as a character class, so the alert resolves on the next scan —
   the lint's behavior is unchanged.
2. Alert #245's `weakened` fixture regex is anchored so it can only match
   at a defined position, while still missing the planted
   `next/font/google` violation (the harness row stays meaningful).
3. Alert #300's `QUOTE_CTL` matches the identical byte set
   (C0 minus TAB, plus DEL) with no multi-character range.

### Cut List (Phase 0.6b)

- None. No new mechanism is proposed — three localized pattern edits.

### Key files

- `scripts/lint-anthropic-content-position.py:32-39` — `POSITIONAL`
  `re.VERBOSE` literal; flagged text is the trailing comment
  `[x.y.length-1]` on line 35.
- `apps/web-platform/test/no-network-fonts.test.ts:475` — `weakened`
  fixture regex; consumer `sweep()` at line 119-133 calls
  `pattern.test(text)` on whole file contents (canonical `FORBIDDEN` at
  line 68 is unanchored by design — outside this alert's scope).
- `scripts/ci-pr-affected-replay.py:1771` — `QUOTE_CTL`; consumer
  `QUOTE_CTL.search(line)` at line 1922 gates field quoting; must NOT
  match bytes >= 0x80 (UTF-8 text must not be quoted).

### Test suites covering the changed code

- `scripts/lint-anthropic-content-position.test.sh` (always-on live
  suite `scripts/lint-anthropic-content-position-live`).
- `bun test`/`vitest` on `apps/web-platform/test/no-network-fonts.test.ts`
  (web-platform unit arm consumes `WEBPLAT_APP_PATHS`).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (3 shards a/b/c).

### Institutional learnings

- `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` — `sec: CodeQL
  alert #N` issues auto-close once referenced alerts leave `open`; the PR
  body still carries `Closes #9550` per operator instruction.
- Functional overlap (Phase 1.5b): no community artifact can repair a
  repo-internal regex defect — assessed inline, no agent spawn
  (depth-1 harness: no subagent spawn capability).

## Files to Edit

- `scripts/lint-anthropic-content-position.py` — reword the line-35
  trailing comment so it contains no `[...]`-shaped text (e.g.
  `# literal index or x.y.length-1`), removing the `h-1` empty-range
  surface. Pattern text and behavior unchanged.
- `apps/web-platform/test/no-network-fonts.test.ts` — anchor the
  `weakened` fixture at line 475
  (`/^https?:\/\/fonts\.googleapis\.com$|^https?:\/\/fonts\.gstatic\.com$/`),
  preserving the "weakened vs canonical" asymmetry the RED row needs.
- `scripts/ci-pr-affected-replay.py` — replace `QUOTE_CTL`'s
  `[\x00-\x08\x0a-\x1f\x7f]` ranges with a programmatically enumerated
  class (C0 minus TAB 0x09, plus DEL 0x7f) — byte-identical match set, no
  range syntax.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#222 — scripts/lint-anthropic-content-position.py:33 — py/overly-large-range (medium)" | Files-to-Edit entry 1 | mapped |
| 2 | "#245 — apps/web-platform/test/no-network-fonts.test.ts:475 — js/regex/missing-regexp-anchor (high; tracker issue #9550)" | Files-to-Edit entry 2 | mapped |
| 3 | "#300 — scripts/ci-pr-affected-replay.py:1771 — py/overly-large-range (medium)" | Files-to-Edit entry 3 | mapped |
| 4 | "PR body MUST include `Closes #9550` on its own line" | AC-4 | mapped |
| 5 | "Commit author: repo's CLA identity, never devin-ai-integration[bot]" | AC-5 | mapped |
| 6 | "For each: real regex defect … fix the pattern — or false positive (leave open, note in PR body; do NOT dismiss without operator sign-off)" | AC-1/AC-2/AC-3 disposition | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `lint-anthropic-content-position.py` | "#222 — scripts/lint-anthropic-content-position.py:33 — py/overly-large-range" | asked |
| Edit `no-network-fonts.test.ts` | "#245 — apps/web-platform/test/no-network-fonts.test.ts:475 — js/regex/missing-regexp-anchor" | asked |
| Edit `ci-pr-affected-replay.py` | "#300 — scripts/ci-pr-affected-replay.py:1771 — py/overly-large-range" | asked |
| `Closes #9550` in PR body | "PR body MUST include `Closes #9550` on its own line" | asked |
| CLA-identity commit author | "Commit author: repo's CLA identity, never devin-ai-integration[bot]" | asked |
| Run the three covering suites | — | inferred — justification: semantics-preservation must be proven, not asserted; each file has a dedicated suite |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `apps/web-platform`
- Planned files: 3 | Estimated changed lines: ~10
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (operator already batched)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/test tooling fix.

## Acceptance Criteria

- [ ] AC-1: `scripts/lint-anthropic-content-position.py` contains no
  `[x.y.length-1]`-shaped comment text inside `POSITIONAL`; the compiled
  pattern and lint verdicts are unchanged.
- [ ] AC-2: `weakened` in `no-network-fonts.test.ts` carries `^`/`$`
  anchors; the "harness rows" RED test still passes (weakened misses the
  planted violation, canonical `FORBIDDEN` catches it).
- [ ] AC-3: `QUOTE_CTL` in `ci-pr-affected-replay.py` matches the
  identical byte set (verified: C0 except 0x09, plus 0x7f) with no
  multi-character range literal.
- [ ] AC-4: PR body contains `Closes #9550` on its own line.
- [ ] AC-5: all commits authored by `Jean Deruelle
  <jean.deruelle@jikigai.com>` — never `devin-ai-integration[bot]`.
- [ ] AC-6: the three covering suites are green (lint-anthropic live
  suite; no-network-fonts vitest file; ci-pr-affected-replay shards).

## Test Scenarios

- Given the reworked `POSITIONAL` literal (unit), when the lint's own
  test suite runs, then verdicts are byte-identical to pre-change
  (comment-only edit) — `bash scripts/lint-anthropic-content-position.test.sh`.
- Given the anchored `weakened` fixture (unit), when
  `no-network-fonts.test.ts` runs, then the "harness rows" RED test
  passes — `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/no-network-fonts.test.ts` (vitest `unit` project — bun test is
  discovery-blocked by `bunfig.toml` `pathIgnorePatterns = ["**"]`).
- Given the enumerated `QUOTE_CTL` (unit), when a property probe compares
  `QUOTE_CTL.search` over bytes 0x00-0xFF against the old class, then
  the match sets are identical — inline `python3` equivalence check plus
  `bash plugins/soleur/test/ci-pr-affected-replay.test.sh`.

## Context

- Alert #222 is a CodeQL **VERBOSE-mode false positive** (comment text
  parsed as a character class); the fix removes the misleading comment
  shape rather than dismissing — the alert self-resolves on the next
  scan, no operator sign-off for dismissal needed.
- Alerts #245/#300 are **real defect shapes** fixed in place.
- `Reviewed-Coverage: sequential-fallback` — this pipeline runs inside a
  depth-1 subagent (no Task/Skill tool); fan-out steps run inline
  sequentially per `token-discipline.md` §Depth-1.
