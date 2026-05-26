---
title: "fix(bug-fixer): skip [Content Publisher] operational notifications"
type: bug-fix
classification: workflow-hardening
lane: single-domain
semver: patch
status: planned
created: 2026-05-15
branch: feat-one-shot-bug-fixer-content-publisher-skip
issue: null
related_issues: [2738, 2863, 3284, 3467, 3073, 2489, 1886, 3765, 1082, 2488, 2353]
requires_cpo_signoff: false
---

# fix(bug-fixer): skip [Content Publisher] operational notifications

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** 3 (Phase 1 regex semantics, Phase 5 actionlint baseline, Acceptance Criteria — added AC10 baseline-delta + Phase 4.6 gate evidence)
**Gates run:** Phase 4.5 (network-outage) — skipped (no triggers); Phase 4.6 (User-Brand Impact) — PASSED (heading present, valid `none` threshold, file not in sensitive-path regex so no scope-out reason required); rule-id citations — N/A (none cited); cited PR/issue numbers verified live.

### Key Improvements

1. **Pre-existing actionlint baseline captured.** `actionlint` already reports one SC2016 warning at `scheduled-bug-fixer.yml:97` (unrelated single-quote issue inside the `Select issue` step) — AC6 must compare against this baseline, not assert "exits 0".
2. **Sibling-workflow precedent located.** `.github/workflows/scheduled-daily-triage.yml` uses the same `index("ux-audit") | not` jq pattern (canonical clause source: `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md`). Our extension is consistent with the canonical exclusion shape.
3. **Regex YAML-escape semantics double-checked end-to-end.** The literal-bracket-inside-character-class trap (the `[` in `\[Content Publisher\]` is metacharacter-escaped; the `[` opening `[: \[(]` is bare; the `\[` member inside the class is escaped) survived a fresh `jq -Rr 'test(...)'` round-trip on the exact YAML source form (Phase 4 in plan body).

### New Considerations Discovered

- **The fix-issue skill's `--exclude-label content-publisher` flag must already be supported.** Confirmed via the canonical reference file `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` — `--exclude-label <label>` is the established skill contract; no skill-side change required (matches Out-of-Scope item).
- **No false-positive collateral risk on `agent:*` titles.** An `[Content Publisher]`-prefixed title would not also carry an `agent:*` label in current corpus (operational notifications are not agent-authored); the new title-regex exclusion is independent of the existing `agent:*` label exclusion and the two cleanly compose.
- **The override (`workflow_dispatch`) path also benefits from the title-regex.** Wait — actually NOT: the override branches at line 98-105 with `OVERRIDE` and skips the jq filter entirely. The `--exclude-label content-publisher` flag in the prompt is therefore the SOLE defense for the override path. Plan Phase 3 already names this — re-emphasized here.

## Overview

Harden `.github/workflows/scheduled-bug-fixer.yml` against `[Content Publisher]` operational-notification issues so the daily bug-fixer no longer burns its full turn budget attempting to "fix" issues that are inherently un-fixable in code.

Two complementary edits to a single file:

1. **Title-regex exclusion** (jq selector at line 142) — extend the current `^(flaky|flake|test-flake|test)[:(]` to also match `[Content Publisher]` titles, broadening the trailing punctuation class to handle the `]` that follows the new branch and the space-delimited continuation `[Content Publisher] X API failed...`.
2. **Prompt defense-in-depth** (line 171) — add `--exclude-label content-publisher` to the `/soleur:fix-issue` invocation so the override path (`workflow_dispatch` with explicit `issue_number`) is also protected.

## Problem

Run `25908353568` (2026-05-15) failed with `error_max_turns` after 56 turns ($2.52 wasted) on issue #2738, `[Content Publisher] LinkedIn API failed -- manual posting required for Soleur vs. Devin (LinkedIn Company Page)`. The issue is an operational notification (a manual posting prompt produced by `scripts/content-publisher.sh`), not a code bug, so `/soleur:fix-issue` cannot make code progress and exhausts the budget.

**Root cause chain:**

1. `scripts/content-publisher.sh` creates these issues with labels `action-required,content-publisher` (see lines 197, 214, 227, 323, 397, 452).
2. The daily triage agent re-labels them as `type/bug + priority/p1-high + domain/marketing` (mis-classifying operational notifications as bugs).
3. The bug-fixer's selection filter (`scheduled-bug-fixer.yml:135-144`) only excludes `bot-fix/attempted`, `ux-audit`, `agent:*`, `synthetic-test`, and the flaky/test title regex — none of which catches `[Content Publisher]` titles or the `content-publisher` label.
4. When users strip the `content-publisher` label during routine issue management, the last line of label-based defense disappears.

The 8 in-flight issues at the time of the incident have already been remediated out-of-band (`type/bug` stripped; `content-publisher` restored on #2738 and #2863). This PR is the workflow patch to prevent recurrence.

## User-Brand Impact

**If this lands broken, the user experiences:** continued turn-budget burn on un-fixable issues — wasted Anthropic API spend on the scheduled run, no actual user-facing regression because no code ships from these failed runs.

**If this leaks, the user's data / workflow / money is exposed via:** none — this is an internal CI cost-control patch. The protected operation (post-by-hand prompt) is operator-only and never touches user data.

**Brand-survival threshold:** none. No single-user incident or aggregate-pattern brand risk. Cost-of-failure is bounded Anthropic spend per run (≈$2.50/day worst case) and operator distraction from spurious bot-fix PRs.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified 2026-05-15) | Plan response |
| --- | --- | --- |
| Current regex is `^(flaky\|flake\|test-flake\|test)[:(]` | Confirmed at `scheduled-bug-fixer.yml:142` (single-line jq test in the `gh issue list` pipeline). | Edit at this exact site. |
| Prompt is `/soleur:fix-issue <N> --exclude-label ux-audit --exclude-label 'agent:*'` | Confirmed at `scheduled-bug-fixer.yml:171`. | Append `--exclude-label content-publisher`. |
| `scripts/content-publisher.sh` emits issues with labels `action-required,content-publisher` | Confirmed at `scripts/content-publisher.sh:201, 219, 230, 327, 401, 452` (`create_dedup_issue` calls). | Reference in updated rationale comment. |
| 8 known [Content Publisher] titles match the new regex | Verified via `jq test()` against 6 representative live titles from `gh issue list --search "[Content Publisher] in:title"` (LinkedIn / Bluesky / Discord / IndieHackers / Hacker News / Partial X thread variants). | Encoded in TR1 below. |
| New regex does NOT false-positive on `bug(content-publisher):` / `review: content-publisher ...` legitimate bug titles | Verified — both return `false` on the new regex test. | Encoded in TR3. |

## Files to Edit

- `.github/workflows/scheduled-bug-fixer.yml` (two regions: jq selector lines 115-144, prompt at line 171; plus the rationale comment block at lines 122-128)

## Files to Create

None.

## Open Code-Review Overlap

None — no open `code-review` issues touch `.github/workflows/scheduled-bug-fixer.yml`. Check ran 2026-05-15 against `gh issue list --label code-review --state open --json number,title,body --limit 200` followed by `jq` body-contains scan for the file path.

## Implementation Phases

### Phase 1 — Edit jq title-regex exclusion

**Location:** `.github/workflows/scheduled-bug-fixer.yml:142`

**Current line:**

```yaml
                  (.title | test("^(flaky|flake|test-flake|test)[:(]"; "i") | not) and
```

**New line:**

```yaml
                  (.title | test("^(\\[Content Publisher\\]|flaky|flake|test-flake|test)[: \\[(]"; "i") | not) and
```

**Key encoding details:**

- The `[` and `]` inside `\[Content Publisher\]` must each be backslash-escaped because they are jq regex metacharacters. Inside a YAML double-quoted string, the literal regex escape `\[` is written `\\[` (YAML eats one level of backslash before the regex engine sees it).
- The trailing character class widens from `[:(]` to `[: \[(]` — it now accepts a colon (legacy flaky/test), a space (Content Publisher's `[Content Publisher] LinkedIn ...`), a `[` (the literal `[` in `[Content Publisher]` is followed by an `L`, so the space form is the operative match; `[` retained for future bracket-prefix titles), or `(` (legacy `test(scope):` form). The space class member is the load-bearing addition for Content Publisher.
- Case-insensitive flag `"i"` preserved.

### Phase 2 — Update rationale comment block

**Location:** `.github/workflows/scheduled-bug-fixer.yml:122-128`

**Current block:**

```yaml
          # - synthetic-test: repo-canonical label for test-only issues.
          # - title regex ^(flaky|flake|test-flake|test)[:(]: skips flaky/test-
          #   investigation reports which the fix-issue skill's single-file
          #   constraint cannot resolve. Intentional over-match on `test:`
          #   covers issues like #2505 ("test: X flake in parallel runs"); a
          #   legitimate `type/bug` titled `test: add coverage` is rare and
          #   would be better handled by /soleur:work anyway.
```

**New block (additions only — existing flaky rationale preserved verbatim):**

```yaml
          # - synthetic-test: repo-canonical label for test-only issues.
          # - title regex (.[Content Publisher]|flaky|flake|test-flake|test)[: \[(]:
          #   - [Content Publisher] branch: skips operational-notification issues
          #     created by scripts/content-publisher.sh (LinkedIn/Bluesky/Discord/
          #     IndieHackers/Hacker News/X manual-posting prompts). These issues
          #     are post-by-hand reminders, not code defects -- the fix-issue
          #     skill cannot make progress and burns the entire turn budget.
          #     Belt-and-braces with the prompt's --exclude-label content-publisher
          #     below: the label survives if the triage agent strips type/bug but
          #     the title-regex survives if a user strips content-publisher.
          #     Triggered by run 25908353568 (2026-05-15, $2.52 wasted on #2738).
          #   - flaky/test branch: skips flaky/test-investigation reports which
          #     the fix-issue skill's single-file constraint cannot resolve.
          #     Intentional over-match on `test:` covers issues like #2505
          #     ("test: X flake in parallel runs"); a legitimate `type/bug`
          #     titled `test: add coverage` is rare and would be better handled
          #     by /soleur:work anyway.
```

### Phase 3 — Add `--exclude-label content-publisher` to prompt

**Location:** `.github/workflows/scheduled-bug-fixer.yml:171`

**Current line:**

```yaml
            Run /soleur:fix-issue ${{ steps.select.outputs.issue }} --exclude-label ux-audit --exclude-label 'agent:*'
```

**New line:**

```yaml
            Run /soleur:fix-issue ${{ steps.select.outputs.issue }} --exclude-label ux-audit --exclude-label 'agent:*' --exclude-label content-publisher
```

Rationale: when an operator triggers `workflow_dispatch` with a specific `issue_number`, the jq filter is bypassed (lines 98-105 short-circuit on `OVERRIDE`). The prompt-level `--exclude-label content-publisher` is the defense-in-depth that the fix-issue skill consults inside its own work loop.

### Phase 4 — Local verification (before commit)

Reproduce the three regex test cases against the new pattern using the same `jq test()` form as the workflow:

```bash
# Test fixture: 6 known [Content Publisher] titles (representative sample)
cat <<'EOF' > /tmp/cp-titles.txt
[Content Publisher] LinkedIn API failed -- manual posting required for Soleur vs. Devin: AI Software Engineer vs. AI Organization (LinkedIn Company Page)
[Content Publisher] Bluesky API failed -- manual posting required for Soleur vs. Paperclip: Domain Intelligence vs. AI Company Orchestration
[Content Publisher] Partial X thread -- resume for Some Case
[Content Publisher] Discord posting failed -- manual posting required for Some Case
[Content Publisher] Post to IndieHackers: Why Most Agentic Tools Plateau
[Content Publisher] Post to Hacker News: Why Most Agentic Tools Plateau
flaky: foo test failure
flake: bar
test-flake: baz
test: add coverage
test(api): something
fix(api): handle null user
feat: add login
bug(content-publisher): stale-content alert misrouted to Discord
review: content-publisher create_dedup_issue missing --milestone
EOF

while IFS= read -r line; do
  matched=$(echo "$line" | jq -Rr '. | test("^(\\[Content Publisher\\]|flaky|flake|test-flake|test)[: \\[(]"; "i") | tostring')
  printf "%-7s | %s\n" "$matched" "$line"
done < /tmp/cp-titles.txt
```

**Expected output (verified 2026-05-15 in this session):**

| Title | Should match? |
| --- | --- |
| `[Content Publisher] LinkedIn API failed ...` | `true` |
| `[Content Publisher] Bluesky API failed ...` | `true` |
| `[Content Publisher] Partial X thread ...` | `true` |
| `[Content Publisher] Discord posting failed ...` | `true` |
| `[Content Publisher] Post to IndieHackers: ...` | `true` |
| `[Content Publisher] Post to Hacker News: ...` | `true` |
| `flaky: foo test failure` | `true` |
| `flake: bar` | `true` |
| `test-flake: baz` | `true` |
| `test: add coverage` | `true` |
| `test(api): something` | `true` |
| `fix(api): handle null user` | `false` |
| `feat: add login` | `false` |
| `bug(content-publisher): stale-content alert misrouted` | `false` (legitimate code bug) |
| `review: content-publisher create_dedup_issue missing --milestone` | `false` (legitimate code review) |

The two `false` results on `bug(content-publisher)` and `review: content-publisher` are the load-bearing non-regression — those titles are legitimate fixable issues and must NOT be swept up by the broader regex.

### Phase 5 — YAML syntax check

Single-file workflow change; run before commit:

```bash
yamllint .github/workflows/scheduled-bug-fixer.yml || true   # lint advisory
actionlint .github/workflows/scheduled-bug-fixer.yml         # workflow-shape check
```

`actionlint` is the canonical gate for GitHub Actions YAML — `bash -n` does not apply to YAML files with embedded shell (see plan sharp-edge re. YAML-vs-bash parse errors).

### Research Insights — actionlint baseline captured 2026-05-15

Pre-edit `actionlint .github/workflows/scheduled-bug-fixer.yml` reports exactly one warning, unrelated to this PR's edits:

```
.github/workflows/scheduled-bug-fixer.yml:97:9: shellcheck reported issue in this script:
SC2016:info:38:10: Expressions don't expand in single quotes, use double quotes for that [shellcheck]
```

This is a SC2016 info-level warning inside the `Select issue` step's heredoc (the `--jq '...'` single-quoted string). It is intentional — the jq expression is meant to be evaluated by jq, not interpolated by shell. AC6 below is updated to specify the **delta** (no NEW warnings beyond this baseline) rather than "exits 0".

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Regex extension applied.** `grep -nE '\\\[Content Publisher\\\]\|flaky\|flake\|test-flake\|test' .github/workflows/scheduled-bug-fixer.yml` returns the updated jq `test(...)` line and that line contains the character class `[: \\[(]` (broadened from `[:(]`).
- [ ] **AC2 — Prompt exclude-label added.** `grep -nE -- '--exclude-label content-publisher' .github/workflows/scheduled-bug-fixer.yml` returns exactly one match on the `Run /soleur:fix-issue ...` prompt line.
- [ ] **AC3 — Rationale comment updated.** `grep -nE 'scripts/content-publisher\.sh' .github/workflows/scheduled-bug-fixer.yml` returns ≥1 match inside the filter-rationale comment block (lines ~122-140); the comment names the regex branch and the run-id `25908353568`.
- [ ] **AC4 — Title-regex matches all known operational-notification shapes.** Running the Phase 4 verification script yields `true` for all 6 `[Content Publisher]` rows AND all 5 flaky/test rows.
- [ ] **AC5 — Title-regex does NOT false-positive on legitimate bug/feat/fix/review/bug-with-content-publisher-scope titles.** Phase 4 script yields `false` for `fix(api): handle null user`, `feat: add login`, `bug(content-publisher): ...`, and `review: content-publisher ...`.
- [ ] **AC6 — actionlint baseline-delta clean.** `actionlint .github/workflows/scheduled-bug-fixer.yml` returns the same one pre-existing SC2016 warning at line 97:9 (captured 2026-05-15, see Phase 5 Research Insights) and zero NEW errors/warnings. Capture pre-edit output as baseline; diff against post-edit output; assert delta is empty.
- [ ] **AC7 — No collateral edits.** `git diff main -- .github/workflows/scheduled-bug-fixer.yml | grep -cE '^[+-]'` shows changes only in (a) the jq `test(...)` line at ~line 142, (b) the comment block at ~lines 122-140, and (c) the prompt line at ~line 171. No edits to any other file in the PR diff.
- [ ] **AC8 — PR body contains `## Changelog` section.** Per task framing, PR body must have a `## Changelog` heading enumerating the user-visible change ("bug-fixer skips Content Publisher operational notifications").

### Post-merge (operator)

- [ ] **AC9 — Next scheduled run skips Content Publisher backlog.** After merge, on the next 06:00 UTC `scheduled-bug-fixer.yml` run (or via `gh workflow run scheduled-bug-fixer.yml`), the `Select issue` step does NOT pick any of the currently-open `[Content Publisher]` issues; the chosen issue (if any) is verified via `gh run view <run-id> --log` to be a non-Content-Publisher title. Verification automated via `gh run view` + `grep "Selected issue"`.
- [ ] **AC10 — Sibling-clause precedent preserved.** `grep -nE 'index\("(ux-audit\|synthetic-test\|bot-fix/attempted)"\) \| not' .github/workflows/scheduled-bug-fixer.yml` returns exactly the same three matches as before the edit (3 label-exclusion clauses). The existing canonical `agent:*` clause (`any(startswith("agent:")) | not`) also returns its pre-existing single match. The PR adds NO new label-exclusion clauses to the jq selector — the title-regex is the right encoding location for `[Content Publisher]` because labels can be stripped, but titles are stable.

## Test Scenarios

Encoded above in Phase 4 (regex behavior) and AC6 (actionlint). No new test files are required — this is a workflow-config change verified by:

1. The shell-runnable regex test against representative live titles (Phase 4, deterministic).
2. `actionlint` for YAML/workflow shape.
3. Post-merge real-run observation of the `Select issue` output (AC9).

The plan deliberately does NOT add a bats/python test harness for this regex because:

- The only regex consumer is the jq pipeline in this single workflow file; there is no shared filter library to test against.
- The Phase 4 test script is the reproducible verification; adding a test framework would exceed the "single-file workflow change" scope and trip the `cq-test-fixtures-synthesized-only` and "no new dependencies" framings.

## Domain Review

**Domains relevant:** Engineering (CI/CD workflow hardening). No Product / Marketing / Legal / Security / Data / Brand / Compliance implications — this is a cost-control change to a scheduled CI workflow that filters which issues a bot agent attempts; no user-facing surface, no data flow, no schema, no auth, no external API contract.

Single-domain Engineering change. No domain-leader spawns needed (per `lane: single-domain` and the brainstorm-carry-forward gate — there's no brainstorm because the task framing already encoded the full design decision).

No cross-domain implications detected — workflow hardening only.

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Regex false-negative — a future `[Content Publisher]` title shape (e.g., `[content-publisher]` lowercase, or a new variant) escapes the filter | low | The `"i"` case-insensitive flag covers casing variants. Other bracketed prefixes the publisher might emit (e.g., `[Content Publisher: failure]`) still match the leading `\[Content Publisher\]` literal. The defense-in-depth `--exclude-label content-publisher` on the prompt is the second layer if the title shape ever shifts. |
| Regex false-positive — a legitimate bug title beginning `[Content Publisher]` exists | very low | Verified via `gh issue list --search "[Content Publisher] in:title"` — every existing match is an operational notification (n=20+). A legitimate code-bug about the publisher would be titled `bug(content-publisher): ...` or `fix(content-publisher): ...` (codebase convention, verified via title search), which the regex correctly leaves alone (AC5). |
| Label-stripping returns — operators strip `content-publisher` AND triage adds `type/bug` AND someone retitles the issue | very low | All three would have to occur simultaneously. The title regex is the highest-leverage defense because titles are rarely rewritten by humans (the publisher's `manual posting required for <CASE_NAME>` shape is stable). |
| YAML escape gotcha — the `\\[` inside a YAML double-quoted string is incorrectly emitted as `\[` (still a valid jq regex escape) or `\\\\[` (broken) | low | Phase 4 verification reproduces the exact in-workflow form using the same `jq -Rr 'test("...")'` pipeline. AC4 is the canary. |
| Prompt-line edit breaks the multi-line `prompt: \|` block formatting | low | Single-line edit appending one flag to an existing argument list; preserves the leading 12-space indentation and the `Run /soleur:fix-issue ...` template. AC2 verifies the line is still grep-matchable as a single occurrence. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with `threshold: none, reason: internal CI cost-control patch with no user-facing surface or data flow`.
- Inside a YAML double-quoted string, `\\` collapses to `\` before the regex engine sees it. The pattern `^(\\[Content Publisher\\]|flaky|flake|test-flake|test)[: \\[(]` is the **YAML source form** — what jq receives is `^(\[Content Publisher\]|flaky|flake|test-flake|test)[: \[(]`. Confirmed equivalence via Phase 4 script (which runs the literal YAML form through `jq -Rr 'test(...)'`).
- Don't conflate the `[` inside `\[Content Publisher\]` (literal, must be escaped) with the `[` opening the trailing character class `[: \[(]` (regex metacharacter, must NOT be escaped). The class opener is bare; the literal inside the class IS escaped because the class also contains `(` and `:` as plain members but we want `[` to be a literal too.
- The rationale comment update must keep the existing flaky/test paragraph intact — `wg-when-an-audit-identifies-pre-existing` and `rf-review-finding-default-fix-inline` would force in-PR cleanup of unrelated changes. Keep the diff focused on Content Publisher additions; preserve the historic flaky/test rationale verbatim.
- `actionlint` may already report pre-existing baseline warnings unrelated to this change (e.g., `runs-on: ubuntu-latest` vs pinned version). AC6 specifies "exits 0 (no new errors beyond pre-existing baseline)" — capture pre-edit `actionlint` output as baseline before applying the edit; compare delta.

## PR Body — Changelog Section (required)

When opening the PR, include this exact section in the body (per task framing `## Changelog section in PR body required`):

```markdown
## Changelog

- **Fixed:** `scheduled-bug-fixer.yml` no longer attempts to auto-fix `[Content Publisher]` operational-notification issues created by `scripts/content-publisher.sh`. Previously, mislabeled Content Publisher issues (e.g., #2738) would burn the agent's full 55-turn budget producing no fixable code change.
- **Added:** `--exclude-label content-publisher` defense-in-depth on the `workflow_dispatch` override path.
- **Triggered by:** run 25908353568 (2026-05-15) error_max_turns at 56 turns ($2.52).
- **Out of scope (deferred):** daily-triage label-correction logic and `scripts/content-publisher.sh` self-labeling tightening.
```

## Out of Scope

- **Daily triage agent label-correction.** The triage agent re-applies `type/bug + priority/p1-high + domain/marketing` to Content Publisher issues. Fixing that is a separate concern (different file: `.github/workflows/scheduled-triage.yml` or wherever triage lives). Defer.
- **`scripts/content-publisher.sh` self-labeling.** The script already applies `action-required,content-publisher`. Tightening it (e.g., to also apply a `not-a-bug` label) is out of scope per the task framing.
- **`/soleur:fix-issue` skill internals.** The skill already supports `--exclude-label <label>`; no internal change needed.
- **Backfill / mass-relabel of existing Content Publisher issues.** Task framing states these have already been remediated out-of-band.

## Merge / Labels

- **Labels to apply at PR open:** `semver:patch`, `domain/engineering`, `chore`, `priority/p2-medium` (all verified via `gh label list --limit 200` 2026-05-15).
- **Auto-merge eligibility:** NO. Per task framing, single-file workflow changes under `.github/` require human review and cannot auto-merge — even though file count is 1, the file is a GitHub Actions workflow. The bug-fixer's auto-merge gate already gates on `priority/p3-low` and a `bot-fix/auto-merge-eligible` label; this PR is `priority/p2-medium` and human-authored, so it routes to human review by default.
- **Closes / Ref convention:** No specific issue to close (the 8 in-flight issues were remediated out-of-band; this is a preventive workflow patch). PR body uses `Ref:` not `Closes:` for the related Content Publisher issue list to avoid auto-closing remediation-tracking issues at merge.

## Verification Commands (one-shot for the implementer)

```bash
# 1. Apply the three edits to .github/workflows/scheduled-bug-fixer.yml (Phases 1-3).

# 2. Regex round-trip (Phase 4):
bash -c 'cat <<EOF | while IFS= read -r line; do
  echo "$line" | jq -Rr ". | test(\"^(\\\\[Content Publisher\\\\]|flaky|flake|test-flake|test)[: \\\\[(]\"; \"i\") | tostring" | xargs -I{} printf "%-7s | %s\n" "{}" "$line"
done
[Content Publisher] LinkedIn API failed -- manual posting required for X
[Content Publisher] Partial X thread -- resume for Y
flaky: foo
test: bar
test(api): baz
fix(api): handle null
feat: login
bug(content-publisher): real bug
EOF'

# 3. Workflow lint:
actionlint .github/workflows/scheduled-bug-fixer.yml

# 4. Diff sanity:
git diff main -- .github/workflows/scheduled-bug-fixer.yml | head -80
```

## Related

- `scripts/content-publisher.sh` (issue creator — see lines 201, 219, 230, 327, 401, 452 for `create_dedup_issue` calls).
- `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` (canonical `--exclude-label` semantics).
- `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` (sibling pattern for label-based exclusion).
- `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` (max-turns/timeout calibration — the existing 45-min / 55-turn budget is preserved by this patch).
- Run `25908353568` (2026-05-15, error_max_turns at 56 turns, $2.52, issue #2738) — incident that triggered this PR.
- Related Content Publisher issues observed: #2738, #2863, #3284, #3467, #3073, #2489, #1886, #3765, #1082, #2488, #2353 (sample of historical operational notifications — not closed by this PR).
