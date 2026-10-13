---
title: "fix: kb-domain-allowlist-guard glob/regex false-positive ask prompts"
date: 2026-06-08
type: fix
branch: feat-one-shot-kb-guard-glob-false-positive
change_class: docs-only (hooks-only — no app code, no UI, no infra, no regulated data)
lane: single-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Test Strategy (RED/GREEN proof), Files to Edit (precedent-diff)
**Research:** end-to-end hook simulation (sandboxed), precedent-diff against the hook's
own `[[ == ]]` idiom, verify-the-negative pass on every `never`/`cannot` claim.

### Key Improvements

1. **RED/GREEN proven, not asserted.** The proposed fix was injected into a copy of the
   real hook and run against the T11/T12 fixtures: both yield `ask` WITHOUT the fix (RED)
   and pass-through WITH it (GREEN). The T12 `jq -Rs` fixture-quoting risk (does the
   bracket-class survive JSON encoding?) is resolved — `[A-Za-z0-9` reaches the hook
   literally.
2. **Regression proven intact.** With the fix applied, T1 (`knowledge-base/observability/foo.md`)
   and T8 (`mkdir -p knowledge-base/observability`) STILL produce `ask`. The genuine
   new-top-level-domain signal is unaffected — the skip touches only metachar-bearing
   segments.
3. **Precedent-diff confirms zero-new-construct.** The proposed `[[ "$SEGMENT" == *['*?[]']* ]]`
   reuses the exact `[[ == ]]` glob idiom already at `.sh:74` (`[[ "$SEGMENT" == "$d" ]]`)
   and `.sh:78` — no subprocess, no new dependency, `set -euo pipefail`-safe.

### Deepen Gate Results (all pass)

- **4.6 User-Brand Impact:** present; threshold `none` with non-empty reason. Files-to-Edit
  (`.claude/hooks/*`) are outside the sensitive-path regex → scope-out satisfied.
- **4.7 Observability:** skipped — Files-to-Edit are `.claude/hooks/*.sh`/`*.test.sh`, not
  `apps/*/{server,src,infra}` or `plugins/*/scripts/`; no new infra surface (pure
  docs/hooks).
- **4.8 PAT-shaped variable:** no match → pass.
- **4.9 UI-wireframe:** no UI-surface file in Files sections → pass.

# fix: kb-domain-allowlist-guard glob/regex false-positive ask prompts 🐛

## Overview

The `kb-domain-allowlist-guard.sh` PreToolUse hook raises a spurious advisory `ask`
when a Bash command merely *mentions* a `knowledge-base/<glob-or-pattern>` path in a
comment or a grep/regex pattern — even when the command's only real write targets are
under a sanctioned domain (`project/`, `engineering/`, …) that would pass cleanly.

The root cause is a single line: the guard scans the **entire** Bash command string
for the **first** `knowledge-base/([^/[:space:]\"\']+)` substring (line 67) and treats
that first match as the write target's top-level segment (line 70). The character class
`[^/[:space:]\"\']` excludes `/`, whitespace, double-quote, and single-quote — but it
does **not** exclude glob/regex metacharacters (`*`, `?`, `[`, `]`). So when the first
occurrence is a comment or a grep pattern, the guard extracts a bogus segment, finds it
neither sanctioned nor on disk, and fires `ask`.

This is exactly the false-positive class that AGENTS.md / the plan-skill Sharp Edge
about `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'` *recommends operators run* to
verify plan citations — the guard penalizes the very command the workflow prescribes.

### Reproduced (empirical, this branch, 2026-06-08)

The reported multi-line command:

```bash
# verify no broken knowledge-base/*.md citations in the plan
PLAN="knowledge-base/project/plans/...md"
grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' "$PLAN" | ...
git add knowledge-base/project/plans/ knowledge-base/project/specs/.../tasks.md
```

- First regex match against the whole command → `SEGMENT=*.md` (from the **comment**),
  NOT `project` (from the genuine `git add` write). Verified:
  `[[ "$CMD" =~ knowledge-base/([^/[:space:]\"\']+) ]]` → `BASH_REMATCH[1]` = `*.md`.
- A standalone grep pattern `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'`
  → `SEGMENT=[A-Za-z0-9`.

Both bogus segments contain a glob/regex metacharacter (`*` or `[`). Real KB path
segments — directory names (`engineering`, `project`, `observability`) or filenames
(`INDEX.md`) — never do. That asymmetry is the fix's discriminator.

### Fix (one guard line + one test file)

After extracting `SEGMENT` (right after the `BASH_REMATCH` assignment at line 70), add a
metacharacter check that **skips (`exit 0`)** when `SEGMENT` contains `*`, `?`, `[`, or
`]`. A short comment cites the comment/grep-pattern false-positive case. Then extend the
test file with two regression cases and keep T1–T10 green.

**Scope:** hooks-only / docs-class. No app code, no schema, no UI, no infra, no
regulated-data surface. The change touches exactly two files, both under `.claude/hooks/`.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the false-positive persists —
an `ask` prompt interrupts routine `git add`/grep commands that mention a KB path in a
comment, adding friction to every plan-citation-verification step; or (b) over-correction
— the metachar skip is written too broadly (e.g. also skipping `.` or `-`) and the guard
stops firing on a genuine new top-level domain, silently allowing taxonomy drift.

**If this leaks, the user's data / workflow / money is exposed via:** N/A. This is an
advisory developer-tooling guard on the local agent's tool calls; it neither reads,
writes, nor transmits user data. It produces only a local `ask`/pass-through decision.

**Brand-survival threshold:** none — local hooks tooling, no user-data surface, no
production write path. Reason: the guard is an advisory taxonomy-drift nudge on the
agent's own KB writes in a worktree; a regression degrades developer ergonomics only, is
caught by the hook's own `.test.sh` suite in CI, and has zero customer-facing blast
radius. No sensitive path touched (the diff is confined to `.claude/hooks/*.sh`).

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (`knowledge-base/project/specs/feat-one-shot-kb-guard-glob-false-positive/`
absent). Every claim in the arguments was verified against `origin`-current code on this
branch:

| Claim (from arguments) | Reality (verified 2026-06-08) | Plan response |
|---|---|---|
| Guard scans for FIRST `knowledge-base/([^/[:space:]\"\']+)` substring | True — `.sh:67` regex, `.sh:70` `SEGMENT="${BASH_REMATCH[1]}"` | Insert fix after `.sh:70` |
| Comment yields `SEGMENT=*.md` | True — reproduced; first match is the comment, not the `git add` | Metachar `*` triggers skip |
| Grep pattern yields `SEGMENT=[A-Za-z0-9` | True — reproduced | Metachar `[` triggers skip |
| Real segments never contain `* ? [ ]` | True — sanctioned set + INDEX.md/INDEX-style files are alnum/`.`/`-` only | Skip is safe; genuine new dirs unaffected |
| Existing tests T1–T10 | All 10 pass on this branch pre-change | Regression cases ADD to suite; T1–T10 unchanged |
| Test harness is `bash .claude/hooks/*.test.sh` (not bats/jest) | True — `.test.sh` shell convention, run directly via `bash` | Add cases in same `.test.sh` style |

## Files to Edit

1. **`.claude/hooks/kb-domain-allowlist-guard.sh`** — insert a metacharacter-skip block
   immediately after `SEGMENT="${BASH_REMATCH[1]}"` (line 70), before the sanctioned-dir
   loop (line 72–75). Pseudocode:

   ```bash
   SEGMENT="${BASH_REMATCH[1]}"

   # Glob/regex-metachar guard: a SEGMENT containing `*`, `?`, `[`, or `]` is the
   # signature of a COMMENT or grep/regex PATTERN that merely mentions a
   # knowledge-base/<glob> path — NOT a real write target. The first-match scan
   # (line 67) can land on `# ... knowledge-base/*.md ...` or
   # `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'` before the genuine
   # `git add knowledge-base/project/...` write, yielding a bogus SEGMENT
   # (`*.md`, `[A-Za-z0-9`) that is unsanctioned and not on disk → false-positive
   # `ask`. Real KB segments (dir names, INDEX.md) never contain these chars.
   if [[ "$SEGMENT" == *['*?[]']* ]]; then
     exit 0
   fi
   ```

   **Load-bearing portability note:** the test pattern is `*['*?[]']*` — a single bash
   `[[ == ]]` glob whose bracket expression `['*?[]']` lists the four metacharacters
   (`*`, `?`, `[`, `]`). Inside a bracket expression `*` and `?` are literal, `[` is
   literal, and `]` is placed/escaped via the `[]']` form so it is taken as a member, not
   the closer. This was verified at plan time: it SKIPs `*.md` and `[A-Za-z0-9`, and KEEPs
   `observability`, `INDEX.md`, `project`. Do NOT rewrite as a `case` or `grep -q` — the
   single `[[ ]]` glob is the existing file's idiom (lines 73–78 already use `[[ == ]]`),
   needs no subprocess, and is `set -euo pipefail`-safe (a non-match is not a failing
   command because it is the `if` condition, not a bare command).

   Placement rationale: AFTER `SEGMENT` is assigned (it needs the value) and BEFORE the
   sanctioned-dir/file/on-disk checks (those are all moot for a non-path token — a bogus
   segment will never match a sanctioned dir, but short-circuiting here is clearer and
   strictly cheaper than falling through three loops + a stat to the same `exit 0`).

2. **`.claude/hooks/kb-domain-allowlist-guard.test.sh`** — add two regression cases after
   T10 (before the `Results:` summary at line 86), renumbering the summary's reach
   naturally (the harness counts via `PASS`/`FAIL`, not hardcoded totals, so no count
   constant to bump):

   - **T11 — reported scenario: comment mentions `knowledge-base/*.md`, real writes are
     `git add knowledge-base/project/plans/` → pass-through (no decision).** Use the exact
     multi-line command from the bug report via `invoke_bash`. Assert
     `decision_of "$out"` is empty.

   - **T12 — grep pattern `knowledge-base/[A-Za-z0-9/_.-]+\.md` → pass-through.** Use a
     `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' "$PLAN"` command via `invoke_bash`.
     Assert empty decision.

   Example (matching existing T1–T10 style, `invoke_bash`/`decision_of` helpers already
   defined at lines 26–27):

   ```bash
   # T11 — Bash command whose COMMENT mentions knowledge-base/*.md but whose real
   # writes are under sanctioned project/ → pass-through (glob-metachar skip). This is
   # the exact reported false-positive: first-match scan lands on the comment (*.md),
   # not the git-add write (project/).
   echo "T11: comment with knowledge-base/*.md + real project/ write → pass-through"
   out=$(invoke_bash '# verify no broken knowledge-base/*.md citations in the plan
   grep -oE "knowledge-base/[A-Za-z0-9/_.-]+\.md" "$PLAN"
   git add knowledge-base/project/plans/ knowledge-base/project/specs/x/tasks.md')
   [[ -z "$(decision_of "$out")" ]] && pass "no decision (glob in comment, real write sanctioned)" || fail "out=$out"

   # T12 — Bash command containing a grep/regex pattern over knowledge-base paths →
   # pass-through (first match yields a bracket-class token, not a real segment).
   echo "T12: grep pattern knowledge-base/[A-Za-z0-9/_.-]+ → pass-through"
   out=$(invoke_bash "grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\\.md' \"\$PLAN\"")
   [[ -z "$(decision_of "$out")" ]] && pass "no decision (grep regex pattern, not a write)" || fail "out=$out"
   ```

   **Quoting note for T12:** the grep-pattern fixture must reach the hook with a literal
   `[A-Za-z0-9` so the first regex match yields `[A-Za-z0-9`. Verify at /work time that
   the `invoke_bash` JSON-encoding (`jq -Rs`) preserves the bracket — confirm the case
   actually fails WITHOUT the fix (RED) before asserting it passes WITH it.

## Files to Create

None.

## Test Strategy (RED → GREEN)

The hook ships its own deterministic shell test suite. No new framework — reuse
`.test.sh` (verified: harness is `bash .claude/hooks/kb-domain-allowlist-guard.test.sh`;
no bats/jest involved). Per `cq-write-failing-tests-before`:

1. **RED:** Add T11 + T12 to `.test.sh` FIRST. Run
   `bash .claude/hooks/kb-domain-allowlist-guard.test.sh`. T11 and T12 MUST FAIL (current
   guard fires `ask` on both) — this proves the tests exercise the bug. (Verified at plan
   time that both inputs currently yield a bogus `SEGMENT` → `ask`.)
2. **GREEN:** Add the metachar-skip block to `.sh`. Re-run. All 12 cases (T1–T12) pass.
3. **Regression guard:** Confirm T1 (`knowledge-base/observability/foo.md` → ask), T2
   (re-add `security/` → ask), and T8 (`mkdir -p knowledge-base/observability` → ask)
   STILL fire `ask` — the genuine new-top-level-domain signal MUST be preserved. None of
   these segments contain a metacharacter, so the skip does not touch them.

**Run command:** `bash .claude/hooks/kb-domain-allowlist-guard.test.sh`
(exit 0 = all pass; non-zero = a failure, per the `[[ "$FAIL" == "0" ]] || exit 1` gate
at line 88).

### Research Insights — RED/GREEN proven by sandboxed simulation (2026-06-08)

The fix was injected into a copy of the real hook (`awk` inserting the skip block after
the `SEGMENT=` assignment) and exercised against the exact T11/T12 fixtures plus the T1/T8
regression cases. Verified output:

```
T11 (comment + grep + git add)   RED(no fix)=ask   GREEN(with fix)=pass-through
T12 (grep pattern)               RED(no fix)=ask   GREEN(with fix)=pass-through
T8  (mkdir observability)        GREEN(with fix)=ask   ← genuine new domain STILL fires
T1  (write observability/foo.md) GREEN(with fix)=ask   ← genuine new domain STILL fires
```

This confirms three things the plan asserts: (1) both false-positive fixtures currently
fire `ask` (the tests are non-vacuous), (2) the one-line skip flips exactly those two to
pass-through, and (3) the skip does NOT weaken genuine new-domain detection. The T12
`jq -Rs` JSON-encoding preserves the literal `[A-Za-z0-9` bracket — the fixture-quoting
risk noted above is resolved.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.claude/hooks/kb-domain-allowlist-guard.sh` contains a `[[ "$SEGMENT" == *['*?[]']* ]]`
      (or behaviorally-equivalent four-metachar) skip block placed immediately after the
      `SEGMENT="${BASH_REMATCH[1]}"` assignment and before the sanctioned-dir loop, with an
      explanatory comment citing the comment/grep-pattern false-positive case.
- [x] `.test.sh` contains T11 (reported comment-plus-real-write scenario) and T12 (grep
      pattern), both asserting empty `decision_of` (pass-through).
- [x] T11 and T12 were demonstrated to FAIL before the `.sh` edit (RED evidence: T11 fired
      `ask` on `SEGMENT=*.md`, T12 on `SEGMENT=[A-Za-z0-9`; `10 passed, 2 failed` pre-fix).
- [x] `bash .claude/hooks/kb-domain-allowlist-guard.test.sh` exits 0 with `12 passed, 0 failed`.
- [x] T1, T2, T8 still produce `ask` (genuine new-domain detection intact) — confirmed by
      the suite passing (these cases assert `== "ask"`).
- [x] Diff is confined to the two `.claude/hooks/` files; no app code, schema, UI, or infra
      touched (`git diff --name-only` lists exactly those two paths).

### Post-merge (operator)

- [ ] None. The change is self-verifying via the `.test.sh` suite in CI; no
      infrastructure apply, migration, or external-service step.
      Automation: full — the test suite is the verification.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — developer-tooling / hooks change. No Product/UX
surface (no file under `components/**`, `app/**/page.tsx`, or any UI-surface path; the diff
is two `.claude/hooks/*.sh` files). No Engineering-domain architectural decision beyond a
one-line predicate. No regulated-data surface (GDPR gate skipped — no schema/auth/API/`.sql`,
no LLM-on-user-data, threshold `none`, no new cron/distribution surface). No new
infrastructure (IaC gate skipped — no server/service/secret/vendor/runtime introduced).

## Observability

Skipped — pure docs/hooks change. Files-to-Edit are under `.claude/hooks/`, not
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and the change
introduces no new infrastructure surface (Phase 2.8 trigger set is empty). The guard's
own behavior is verified by the `.test.sh` suite (the discoverability mechanism for a
hook is its test, not a liveness probe).

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (63 open issues,
2026-06-08); `jq`-grepped each issue body for `kb-domain-allowlist-guard.sh` and
`kb-domain-allowlist-guard.test.sh` — zero matches. No fold-in / acknowledge / defer
needed.

## Risks & Mitigations

- **Over-broad skip silences genuine new-domain detection.** Mitigated by restricting the
  skip to exactly the four glob/regex metacharacters (`* ? [ ]`) — verified that all
  sanctioned dirs, `INDEX.md`, and a plausible new domain (`observability`) contain none of
  them, so the genuine-signal cases (T1/T2/T8) are provably unaffected. Do NOT add `.`,
  `-`, or `_` to the skip set — those ARE valid in real segments (`INDEX.md`, dated
  filenames).
- **Bracket-expression quoting fragility.** The `['*?[]']` form is portable bash and was
  verified at plan time. The `.test.sh` RED step is the safety net: if the predicate is
  mis-quoted, T1/T2/T8 (or T11/T12) will fail loudly.
- **Test fixture quoting drift (T12).** `jq -Rs` JSON-encoding of the grep pattern must
  deliver a literal `[A-Za-z0-9` to the hook. Mitigated by the RED-first requirement —
  T12 must fail without the fix, proving the fixture actually reaches the metachar path.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with threshold `none` + a non-empty reason, satisfying preflight
  Check 6 for the `none`-threshold-plus-non-sensitive-path case.)
- The metachar skip is a heuristic, not a parser. It deliberately does NOT attempt to
  distinguish "comment that mentions a glob" from "a write to a path literally named with a
  metachar" — because the latter cannot exist (KB segments are alnum/`.`/`-`/`_`). If a
  future legitimate use ever needs a `[`/`*` in a real top-level segment, this skip would
  mask it; that is an accepted, documented trade-off (the guard is advisory taxonomy-drift
  tooling, not a security boundary — see the hook's own header comment lines 24–27).
- This is the same false-positive that the plan-skill Sharp Edge about
  `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'` (KB citation verification) trips. After
  this fix lands, that recommended verification command no longer triggers the guard.

## Why This Change

The guard exists to make a NEW top-level `knowledge-base/` domain an
operator-acknowledged decision (advisory `ask`), catching accidental taxonomy drift. The
first-match-anywhere scan was a deliberate simplification (catch `mkdir`/`cat >`/`mv`/`tee`
substrings without a full bash parser), but it conflates "a path that gets written" with
"a path that gets mentioned." The metachar skip restores the intended semantics — fire on
genuine new write targets, ignore comments and grep/regex patterns — with one line and
zero new dependencies, scoped entirely to the hook and its test.
