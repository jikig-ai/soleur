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

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** 4 (Observability, Guard Contract, Open Code-Review
Overlap, Context)
**Research agents used:** none — `Reviewed-Coverage: sequential-fallback`
(depth-1 subagent, no Task tool); halt gates 4.6/4.7/4.8/4.9/4.10/4.11/
4.12/4.13/4.55 run inline, all pass.

### Key Improvements

1. Alert #222 root-caused to a `re.VERBOSE` comment parsed as a char
   class (`h-1` empty range) — fix is comment reword, not dismissal.
2. `QUOTE_CTL` equivalence is a byte-set identity (C0 minus TAB + DEL),
   verified by a `python3` probe, not by eyeball.
3. `weakened` keeps its fixture role after anchoring — the RED harness
   row still proves the canonical `FORBIDDEN` catches the planted
   violation.

### New Considerations Discovered

- Sibling `test-all.sh` runs hold the local gate — targeted suites
  substitute for the full battery (rc=4 refusal expected).
- `no-network-fonts.test.ts` is a vitest `repo-wide` project member;
  `bun test` is discovery-blocked (`bunfig.toml`).

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

## Observability

```yaml
liveness_signal:
  what: the three dedicated suites are the guard's heartbeat — lint-anthropic-content-position.test.sh, no-network-fonts vitest, ci-pr-affected-replay shards
  cadence: per-PR via the affected-selector edges; the lint suite is always-on
  alert_target: red required check blocks the PR
  configured_in: scripts/lib/test-affected-paths.sh (ALWAYS_ON list) + apps/web-platform/vitest.config.ts
error_reporting:
  destination: suite stderr lines in the GitHub Actions run log
  fail_loud: each suite exits non-zero with FAIL:<row>; the replay ratchet emits ::error annotations
failure_modes:
  - mode: regex over/under-matches after the edit (weakened guard)
    detection: the three dedicated suites re-run over this diff
    alert_route: required check red on the PR
logs:
  where: GitHub Actions run logs for this PR
  retention: GitHub default retention
discoverability_test:
  command: grep -c QUOTE_CTL scripts/ci-pr-affected-replay.py
  expected_output: "2"
```

## Guard Contract

The deliverable is a bugfix INSIDE two existing guards plus one test
fixture — not a new guard — but the fixes alter the guards' match
semantics, so the contract pins the preserved properties.

### Guard 1 — lint-anthropic-content-position POSITIONAL

**Property.** Any Anthropic-response file selecting a content block by
position (literal index, `.at(N)`, or `x.length - 1`) is rejected; type
selection passes.

**Assembly.** `tracked_files()` enumerates tracked files under
`EXTENSIONS`; every scanned line flows through `POSITIONAL` /
`POSITIONAL_JQ` — the only match chokepoints. The reworded comment is
inside the VERBOSE literal but contributes zero pattern bytes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | delete the `at\(\s*-?\d+\s*\)` alternative | RED (`.at(0)` row) |
| 2 | drop `tracked_files` enumeration → 0 scanned, exit 0 | RED (dispatch/vacuity row) |
| 3 | a second positional select after a compliant first line in one file | RED (both flagged, not first-only) |

### Guard 2 — ci-pr-affected-replay QUOTE_CTL

**Property.** Any emitted field containing a C0 byte other than TAB, or
DEL (0x7f), is quoted; printable ASCII, TAB and bytes >= 0x80 pass raw.

**Assembly.** `quote_field`/`QUOTE_CTL.search` at line 1922 is the sole
quoting chokepoint for emitted rows (gap, ref, stale, unaudited lines).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | enumerate 0x09 into the class → tab fields get quoted | RED (tab fixture expects raw) |
| 2 | drop 0x7f → DEL passes raw through a printed field | RED |
| 3 | `QUOTE_CTL.search` → `False` in `quote_field` (dispatch neutered) | RED (ctl-byte rows) |

### Guard 3 — no-network-fonts sweep + weakened fixture

**Property.** `sweep` flags any swept file referencing `next/font/google`
or the two font CDN hosts; the `weakened` fixture must still miss the
planted `next/font/google` import while canonical `FORBIDDEN` catches it.

**Assembly.** `sweep()` iterates `enumerateWalk` → `isSwept` →
`pattern.test(text)`; `pattern` is `FORBIDDEN` unless the test injects
`weakened`. Anchored `weakened` (this diff) must not match the fixture.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | delete `next\/font\/google` alternative from FORBIDDEN | RED (row-1 violations pass) |
| 2 | neuter `sweep`'s test call (`pattern.test` → `false`) | RED (dispatch/vacuity row) |
| 3 | anchored `weakened` matches the fixture (e.g. anchors dropped) | RED (RED row's `.not.toThrow()` inverts) |

## Open Code-Review Overlap

None — the 200-issue `code-review` query matched zero bodies containing
any of the three planned paths.

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
