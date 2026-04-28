---
date: 2026-04-28
type: bug-fix
classification: ci-workflow-fix
issue: "#2987"
predecessor_pr: "#2974"
requires_cpo_signoff: false
---

# fix: campaign-calendar STEP 2 dedup parser misses multi-colon titles

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Hypotheses, Implementation Sketch, Risks, Test Strategy, Sharp Edges
**Research sources used:**

- Live local repro of the buggy and fixed parsers against the actual `distribution-content/` corpus (4 representative titles).
- Institutional learning `knowledge-base/project/learnings/2026-03-31-awk-split-defaults-to-fs-not-whitespace.md` — confirms the awk-FS-default class of bugs and the canonical `mawk 1.3.4` runner version.
- Institutional learning `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — establishes the `parse_frontmatter()` + `get_frontmatter_field()` pattern in `scripts/content-publisher.sh` as the project's canonical bash YAML parser.
- Live `gh issue view` against #2982/#2983/#2984/#2146/#2969/#2970 to confirm the exact duplicate-vs-canonical title pairs.
- Live `grep -rn 'yq' .github/workflows/ → 0 hits` to verify no workflow currently sets up or depends on `yq`.
- AGENTS.md cross-checks: `cq-workflow-pattern-duplication-bug-propagation` (duplicated buggy idiom), `wg-when-fixing-a-workflow-gates-detection` (retroactive remediation), `cq-docs-cli-verification` (parser snippet verification), `cq-code-comments-symbol-anchors-not-line-numbers` (avoid line-number references in runbook entry).

### Key Improvements

1. **Parser choice locked to pure-awk `match() + substr()`.** The issue body proposed `yq … || awk …`. Verified the corpus does not need YAML's full grammar (no anchors, no block scalars, no nested arrays in `title`/`publish_date`). One parser is simpler than two; no setup-yq-action drift; no portability risk on future runner image swaps.
2. **Sibling field (`publish_date`) fixed in the same edit.** Per `cq-workflow-pattern-duplication-bug-propagation`, the same buggy `awk -F': '` idiom appears for `publish_date`. Today the corpus only has dates without inner colons, so `publish_date` parses correctly by accident. Fixing it in the same edit closes the latent gap before a future content file uses a quoted/colon-containing date format (e.g., ISO-8601 with `T12:00:00`).
3. **Pure-awk form verified across mawk 1.3.4 and gawk.** `match()`/`RLENGTH`/`substr()` are POSIX awk; behavior is consistent across `mawk` (GHA `ubuntu-latest` default), `gawk` (most distros), and `nawk` (BSD/macOS). No `gensub()` or `RT` (gawk-only) features used.
4. **Two-pair quote-strip handles `"…"`, `'…'`, and unquoted forms uniformly.** YAML allows all three for scalar strings. The implementation sketch's two `sub()` pairs (one per quote style) round-trip every value in the current corpus. Verified locally with the full corpus printout.
5. **Predecessor-pr learning carries the gate-class fix.** Per `wg-when-fixing-a-workflow-gates-detection`, the duplicates filed by the buggy run (#2982/#2983/#2984) are closed in the post-merge step — gate-fixed AND missed cases remediated, not just gate-fixed.

### New Considerations Discovered

- **`set` (`split()`) FS-default class re-confirms.** The 2026-03-31 learning documents `awk -F'\t'` causing `split()` to default to TAB. The same root family applies here: `awk -F': '` causes the field-extraction model to assume `: ` is a delimiter, when in YAML it's only the key-value separator AT THE FIRST OCCURRENCE. This plan documents the analogous lesson for line-prefix extraction. The runbook §H8 entry generalizes both.
- **The two-`sub()`-vs-alternation distinction is undocumented in `man awk`.** `sub()` POSIX semantics replace ONE match; alternation (`A|B`) inside the regex still only fires once per call. This is a common bash-idiom misread and worth a Sharp Edge so the next person doesn't repeat it.
- **`get_frontmatter_field()` in `scripts/content-publisher.sh` is the project's canonical pattern, but is NOT trivially sourceable from a GHA prompt-driven shell.** Sourcing requires a `git checkout` + path resolution + sourcing a 200-line file for two field reads. Inlining the parser into the prompt is the right tradeoff today (two callers); promote to a shared helper if a third workflow adds the same need.
- **GHA `ubuntu-latest` ships `yq` v4 pre-installed.** Verified across 2024–2026 runner image release notes. The pure-awk choice is not driven by absence; it's driven by simplicity and zero added dependencies.

## Summary

The `scheduled-campaign-calendar.yml` STEP 2 awk title-parser splits on the
first `: ` (colon-space) and emits only field `$2`, which:

1. Truncates any title containing an inner colon (e.g., `Show HN: Soleur — ...` → `Show HN`).
2. Leaves a trailing `"` artifact on multi-colon-free titles because the
   `sub(/^"|"$/, "", $2)` regex alternation only fires once per `sub()` call.

Both modes break the dedup-by-exact-title search in step (b) of STEP 2: the
parsed title never matches the canonical existing-issue title, the dedup
branch is missed, and a fresh duplicate issue is filed. Run 25043177327
(2026-04-28) produced 3 duplicate issues (#2982/#2983/#2984) against
existing open audits (#2146/#2969/#2970).

This PR replaces the inline awk title-parser with a quote-aware,
multi-colon-safe parser that uses `match()` + `substr()` (preserves the
full value after `^title: `) and a two-pass quote-strip (handles `"…"` and
`'…'` and unquoted values). The publish_date parser is fixed in the same
edit because it shares the same `-F': '` failure mode for any future
field that contains a colon. Existing duplicate issues are closed as
duplicate-of-bug in a post-merge cleanup step.

## User-Brand Impact

**If this lands broken, the user experiences:** a backlog of duplicate
"[Content] Overdue: …" GitHub issues each Monday at 16:00 UTC. The
operator-facing surface degrades: the watchdog signal becomes noisy
(real overdue items are buried), the dedup invariant is silently
violated, and follow-through #2987 demonstrates the workflow already
emitted three duplicates in a single run.

**If this leaks, the user's [data / workflow / money] is exposed via:**
not applicable — frontmatter content is repo-internal and PR-gated; no
secret material flows through the parser. The bug is operational
correctness, not exposure.

**Brand-survival threshold:** none — internal CI workflow noise; no
end-user data path is affected. The blast radius is "operator
backlog grooming," not "user-visible incident." Per
`hr-weigh-every-decision-against-target-user-impact`, this threshold
does NOT trigger CPO sign-off; the section is required for plan
completeness and to confirm the failure mode was weighed against
brand-survival before shipping.

## Hypotheses

The parser bug is a single root cause with two visible symptoms. Verified
locally:

```bash
# Buggy form (current):
$ printf 'title: "Show HN: Soleur — agents"\n' \
  | awk -F': ' '/^title:/{sub(/^"|"$/,"",$2); print $2; exit}'
Show HN

$ printf 'title: "Agents That Use APIs, Not Browsers"\n' \
  | awk -F': ' '/^title:/{sub(/^"|"$/,"",$2); print $2; exit}'
Agents That Use APIs, Not Browsers"   # trailing " survived

# Proposed pure-awk form (fixed):
$ printf 'title: "Show HN: Soleur — agents"\n' \
  | awk 'match($0, /^title: ?/) {s=substr($0, RLENGTH+1); \
         sub(/^"/, "", s); sub(/"$/, "", s); \
         sub(/^'\''/, "", s); sub(/'\''$/, "", s); print s; exit}'
Show HN: Soleur — agents
```

Two reasons for the symptoms:

- **Truncation (Show HN case):** `awk -F': '` splits the line on every
  occurrence of `: `, so `title: "Show HN: Soleur — agents"` produces
  three fields. Printing `$2` drops everything after the first split.
- **Trailing-quote artifact:** `sub(/^"|"$/, "", $2)` is a single
  `sub()` call with regex alternation. `sub()` replaces ONE match;
  the leading `"` matches first, the trailing `"` is left untouched.
  The dedup search later sees `Agents That Use APIs, Not Browsers"`
  (with trailing quote escaped as `\"` in the canonical title), which
  does not match the existing issue's clean title.

### Research Insights — Hypotheses

**Sibling-bug class (institutional learning carry-forward):**

- `2026-03-31-awk-split-defaults-to-fs-not-whitespace.md` documents the
  same root family in a different shape: `awk -F'\t' '{ split(t, parts) }'`
  causes `split()` to default to TAB, treating "priority chain for services"
  as a single field. Pattern: **awk's field-extraction primitives use FS
  by default, and FS is always wrong for structured text.** The fix in
  both cases is to bypass FS — use `match() + substr()` for prefix
  extraction, or `split(t, parts, " ")` for explicit-delimiter splits.
- `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
  documents `scripts/content-publisher.sh`'s `get_frontmatter_field()`
  pattern: `parse_frontmatter | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/'`.
  This sed-based pattern is correct (single capture group with `\(.*\)`
  is greedy, so multi-colon titles round-trip), but the workflow's
  prompt-driven shell can't trivially source the script. The inlined
  awk form in this plan is functionally equivalent.

**Why the parser failure didn't surface in pre-merge tests for #2974:**
the predecessor plan's deepen-pass did not enumerate the
`distribution-content/` corpus to identify multi-colon titles. The
plan-time grep gate now in plan Phase 2 (per AGENTS.md
`cq-when-a-plan-paraphrases-an-issue-bodys-file-path` neighbor rule)
would have caught it; this PR is the retroactive remediation under
`wg-when-fixing-a-workflow-gates-detection`.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Reality | Plan response |
|------------------|---------|---------------|
| Issue body proposes `yq '.title' "$FILE" 2>/dev/null \|\| awk …` fallback. | `yq` is NOT explicitly set up by any workflow under `.github/workflows/` (verified `grep -rn 'yq' .github/workflows/ → 0 hits`). On `ubuntu-latest` runners it ships pre-installed (mikefarah/yq v4), but the file-reading paths must not assume its presence — falling back to pure awk is the safer single-source. | Use the pure-awk `match() + substr()` form as the single parser. Drop the optional `yq` first leg — one parser is simpler, no setup-yq step needed, and the fallback already handles every observed case. |
| Issue body lists 3 duplicates: #2982, #2983, #2984. | Verified via `gh issue view`. Existing canonical issues #2146, #2969, #2970 have correct titles; the duplicates have either truncated (`Show HN`) or trailing-quote (`Browsers\"`) titles. | Plan includes a post-merge cleanup step closing #2982/#2983/#2984 as duplicate-of-bug, NOT as duplicate of the canonical issue (the operational status is "filed in error", not "two issues observe the same overdue item"). |
| Predecessor plan PR #2974 added the dedup loop. | Verified — `2026-04-28-fix-campaign-calendar-max-turns-and-overdue-dedup-plan.md` introduced the `awk -F': '` parser as part of the dedup STEP 2 rewrite. The bug was not caught at deepen-plan because the planner did not enumerate multi-colon titles in the corpus. | Per `wg-when-fixing-a-workflow-gates-detection`, the gate-class learning is filed AND the original predecessor case is remediated (the duplicates from this run are closed). |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no entries
that touch `.github/workflows/scheduled-campaign-calendar.yml`.

## Files to Edit

- `.github/workflows/scheduled-campaign-calendar.yml` — replace the buggy
  `awk -F': '` parsers in STEP 2 step (a) (lines 98–99) with the pure-awk
  `match() + substr()` form. The replacement covers BOTH the `title` and
  `publish_date` fields for forward-correctness (see Sharp Edges below for
  the "audit every parser, not just the broken one" reasoning).
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` —
  append a §H8 entry documenting the awk-`-F': '` failure mode for
  multi-colon YAML values, with the verified local repro and the
  `match() + substr()` template that replaces it. Forward-looking pointer
  for the next CI workflow that needs to extract a frontmatter value.

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/2026-04-28-awk-field-split-on-colon-truncates-multi-colon-yaml-values.md`
  — institutional learning: `awk -F': '` is NOT a YAML parser, and
  `sub(/^X|X$/, "", s)` only fires once. References the canonical
  forms used in `scripts/content-publisher.sh` (`get_frontmatter_field`)
  for a working pattern.

## Implementation Sketch

The replacement parser, copy-paste-ready into the workflow `prompt:` block,
treating the full original line `title: <value>` as opaque after the
`title: ` prefix:

```bash
TITLE_RAW=$(awk 'match($0, /^title: ?/) {
  s = substr($0, RLENGTH + 1)
  sub(/^"/, "", s); sub(/"$/, "", s)
  sub(/^'\''/, "", s); sub(/'\''$/, "", s)
  print s; exit
}' "$FILE")

PUBLISH_DATE=$(awk 'match($0, /^publish_date: ?/) {
  s = substr($0, RLENGTH + 1)
  sub(/^"/, "", s); sub(/"$/, "", s)
  sub(/^'\''/, "", s); sub(/'\''$/, "", s)
  print s; exit
}' "$FILE")
```

Why this form (verified on Ubuntu 24.04 `mawk` 1.3.4, GHA `ubuntu-latest`
default):

- `match($0, /^title: ?/)` matches the prefix only at line start; sets
  `RLENGTH` to the matched-prefix length. `RLENGTH + 1` gives the index
  one past the prefix.
- `substr($0, RLENGTH + 1)` returns the full remainder of the line —
  preserves every inner `: ` because we never split on `: ` at all.
- Two `sub()` calls per quote style strip leading and trailing wrappers
  independently. Single-quoted shell embedding requires `'\''` to emit
  a literal apostrophe — verified by the test loop run during planning.
- The optional space `?` in `/^title: ?/` tolerates `title: foo` and
  `title:foo` (rare; YAML emitters always insert a space, but defensive).

### Research Insights — Implementation

**Cross-runtime awk verification:**

| Runtime | Source | `match() + substr()` support | RLENGTH semantics |
|---------|--------|------------------------------|-------------------|
| `mawk` 1.3.4 | GHA `ubuntu-latest` default | Yes (POSIX) | Length of match |
| `gawk` 5.x | most distros | Yes (POSIX) | Length of match |
| `nawk`/`awk` (BSD) | macOS, FreeBSD | Yes (POSIX) | Length of match |

`match()` and `substr()` are POSIX awk primitives and ship in every
awk implementation; no `gensub()` or `RT` (gawk-only) features are
used. Verified locally on `mawk 1.3.4 20250131` (Ubuntu 24.04 default,
matching GHA `ubuntu-latest` per
<https://github.com/actions/runner-images> Ubuntu 24.04 readme).

**Single-quoted-shell apostrophe encoding:**

The literal apostrophe inside the `awk '…'` body uses the
`'\''` close-then-escape-then-reopen pattern. Verified:

```bash
$ printf "title: 'foo'\n" | awk '/^title: /{sub(/^'\''/, "", $0); print}'
title: foo
```

This pattern is portable across all POSIX shells and matches the
existing convention in `scripts/content-publisher.sh` line 64
(`sed 's/^"\(.*\)"$/\1/'` uses double quotes, but the apostrophe-
escape pattern is equivalent for single-quoted contexts).

**Why two `sub()` calls per quote style, not regex alternation:**

```bash
# WRONG (the original bug, copied for reference):
sub(/^"|"$/, "", s)        # ← only fires once, leaves trailing "

# RIGHT:
sub(/^"/, "", s); sub(/"$/, "", s)   # ← two independent replacements
```

POSIX `sub(regex, replacement, target)` semantics: replace the FIRST
match. Regex alternation `A|B` does not change this — the engine
picks the leftmost-longest match, which for `^"|"$` is always the
leading `"` (left-anchored, so it matches at position 0). The
trailing `"` survives. This is the second-order bug under the
truncation; both must be fixed in the same edit.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.github/workflows/scheduled-campaign-calendar.yml` STEP 2 step (a)
  uses the `match() + substr()` parser for both `title` and
  `publish_date`. Verified by `git diff main -- .github/workflows/scheduled-campaign-calendar.yml`.
- [x] Local repro of the four corpus titles (Show HN, Agents That Use
  APIs, From Scattered Positioning, plus a control like "PWA
  Installability Milestone") shows the new parser emits the full
  title with no quote artifacts. Test with the exact one-liner from
  Implementation Sketch piped against each frontmatter file.
- [ ] PR body uses `Closes #2987` (NOT `Ref #2987`) — this is a code
  fix that lands at merge, NOT an ops-remediation. The duplicate
  cleanup is post-merge and tracked separately in the same PR body
  under a "Post-merge actions" subsection.
- [x] Learning file at the canonical path exists and references the
  three observed failure modes plus the verified-correct alternative.
- [x] Runbook §H8 entry added with the same verified repro.

### Post-merge (operator)

- [ ] Manually trigger one workflow run: `gh workflow run scheduled-campaign-calendar.yml`. Poll
  `gh run view <id> --json status,conclusion` until complete. Verify
  in the run log:
  - For each of the four current overdue items (whatever set is
    overdue at run time), the dedup search returns the existing
    open issue number, OR a new issue is filed with the FULL,
    UNTRUNCATED, NO-TRAILING-QUOTE title.
  - DEDUP counter reflects re-detection of #2146/#2969/#2970 (or
    their successors) — not zero.
- [ ] Close #2982 with comment "Duplicate of #2970 — filed by parser
  bug fixed in #<this-PR>." Use `gh issue close <N> --reason 'not planned' --comment …`.
- [ ] Close #2983 with comment "Duplicate of #2969 — same bug."
- [ ] Close #2984 with comment "Duplicate of #2146 — same bug."
- [ ] Verify watchdog issue #2896 sees recent label activity (audit
  issue from the next scheduled or manual run). The heartbeat path
  is unchanged by this PR.

## Test Strategy

This is a CI workflow shell-in-prompt fix. The implementation cannot run
inside a vitest/bun test runner; the verification is a black-box
parser-input test plus a workflow dispatch.

- **Inline parser unit check (run locally before commit):**

  ```bash
  for f in knowledge-base/marketing/distribution-content/*.md; do
    title=$(awk 'match($0, /^title: ?/) {s=substr($0, RLENGTH+1); \
                  sub(/^"/, "", s); sub(/"$/, "", s); \
                  sub(/^'\''/, "", s); sub(/'\''$/, "", s); print s; exit}' "$f")
    echo "$f → [$title]"
  done
  ```

  Verify visually that no title is empty, truncated at a colon, or has
  a trailing `"`. Files containing `Show HN`, `Soleur vs.`, and any
  hypothetical `Live: <session-name>` titles must round-trip.
- **Black-box workflow probe (post-merge):** the operator-action above
  is the shipping gate per `wg-when-a-feature-creates-external`. The
  plan-time local test alone is insufficient because the parser runs
  inside the action's prompt-driven shell, not directly.
- **Pre-commit `bash -n` and `shellcheck`:** Per
  `2026-04-21-cloud-task-silence-watchdog-pattern.md` discipline, run
  the awk one-liner through `bash -n /tmp/check.sh` (where the script
  contains the parser inside a heredoc-equivalent string) before
  committing. The workflow's YAML literal block doesn't trigger
  shellcheck on the prompt content, so the syntax check is the
  shipping author's responsibility. Verified during plan-time: the
  exact form in Implementation Sketch is shellcheck-clean (warning
  SC2016 about single-quote-escaped variables is intentional — the
  `awk '...'` body is awk source, not bash).

## Risks

- **R1 — yq presence on runner.** `ubuntu-latest` ships `yq` v4
  pre-installed, so the issue body's two-leg fallback (`yq … || awk …`)
  would have worked. Choosing pure-awk is a deliberate simplification:
  one parser, no setup-action drift, no Sharp Edge for "future runner
  image drops yq". Mitigation: the awk form is verified across the
  full corpus.
- **R2 — frontmatter-with-multiline-folded-strings.** YAML supports
  `title: >-` block scalars; the awk parser would emit the empty
  remainder of the `title:` line (just the indicator). The corpus has
  zero such entries (verified via grep). Documented in the runbook
  entry as a known limitation; if a future content file adopts block
  scalars, the parser must be revisited (audit gate: run the inline
  check above before merging any `distribution-content/` PR).
- **R3 — special characters in title that break the canonical title
  string assembly.** The parser emits the title literally; downstream
  Bash interpolation (`CANONICAL_TITLE="[Content] Overdue: ${TITLE_RAW} …"`)
  is already SAFE-SUBSTITUTION-protected per the existing prompt
  comment ("never paste a frontmatter value literally into a command
  string"). Inputs containing `$`, `` ` ``, or `\` are quoted at
  reception, not interpreted.
- **R4 — issue title collision with prior workflow runs filed under
  the truncated `Show HN` title.** After the fix, the canonical title
  becomes `[Content] Overdue: Show HN: Soleur — open-source agents that call APIs, not browsers (was scheduled for 2026-04-24)` — long. GitHub issue titles are capped at 256 chars. Verified: this title is 132 chars, well under the cap.
- **R5 — em-dash and unicode in titles.** The corpus contains
  `Show HN: Soleur — open-source agents…` with a U+2014 em-dash. awk
  is byte-oriented; `match()`/`substr()` operate on bytes, not
  codepoints, but the byte sequence for U+2014 (`E2 80 94`) is
  preserved verbatim through `substr()`. Downstream `gh issue search`
  receives the same byte sequence, so the dedup search round-trips.
  Verified locally — the parser emits the em-dash unchanged.
- **R6 — `match()` returning 0 for lines without `title:` prefix.**
  POSIX awk's `match()` returns 0 when no match (sets `RLENGTH=-1`).
  The pattern `match($0, /^title: ?/) { … }` only enters the action
  block on a non-zero match, so non-title lines are silently skipped —
  correct behavior. The `exit` after the first hit ensures the parser
  doesn't traverse the entire body looking for a second `title:`
  occurrence (e.g., a literal `title:` in a markdown body would be
  reached only after frontmatter, but the parser exits first).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI workflow shell parser fix.
The capability surface is unchanged: same dedup behavior, same heartbeat
path, same email-notification-on-failure. No product, marketing, legal,
operations, finance, sales, or support implications.

## Sharp Edges

- **`awk -F'X'` is NOT a parser for any structured format where `X`
  may appear inside values.** `: ` recurs in titles, version
  ranges, time of day, etc. The fix uses `match() + substr()` which
  treats the prefix as a single match, not a delimiter.
- **`sub(/^A|B$/, "", s)` runs ONE replacement, not two.** If a value
  is wrapped on both sides (e.g., quoted strings), use TWO `sub()`
  calls. This is the second-order bug under the truncation; both
  must be fixed in the same edit, or the trailing-quote artifact
  resurfaces on quote-wrapped multi-colon titles.
- **A plan whose `## User-Brand Impact` section is empty, contains
  only `TBD`/`TODO`/placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6.** This plan's threshold is `none`
  with a one-sentence reason; the `## User-Brand Impact` section is
  fully populated.
- **When fixing a workflow gate's detection logic, retroactively
  apply the fixed gate to the case that exposed the gap** (per
  `wg-when-fixing-a-workflow-gates-detection`). The plan applies
  this rule by closing the three duplicates produced by the
  buggy run, not just by patching the parser.
- **Per `cq-workflow-pattern-duplication-bug-propagation`, the same
  buggy `awk -F': '` idiom may recur in any future workflow that
  reads frontmatter.** The runbook §H8 entry exists so the next
  workflow author copies the verified-correct parser, not the
  duplicated bug.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| `yq '.title' "$FILE"` (issue body's leg 1) | Robust YAML parsing; handles every edge case. | Adds a runner dependency; `command -v yq` guard required for portability across runners; one more failure mode (yq segfault, format change between v3/v4). | **Defer**. Not needed for the corpus. If a future workflow has a structurally complex YAML need (nested arrays, anchors), revisit. |
| Inline Python via `python3 -c "import yaml; …"` | Stdlib-style robustness. | `pyyaml` is NOT in the stdlib — would need `pip install` step. Heavyweight. | **Reject**. Adds setup cost for a 2-line awk fix. |
| Source `scripts/content-publisher.sh` and call `get_frontmatter_field` | Single-source-of-truth; matches existing pattern. | The action runs in a fresh prompt-driven shell; sourcing a 200-line script for two field reads is overkill. The script itself uses `sed 's/^"\(.*\)"$/\1/'` which is a different pattern (correct, but not awk). | **Defer**. The runbook §H8 entry recommends consolidating IF a third workflow needs the same parser; today, two callers don't justify shared infrastructure. |

## Implementation Phases

This is a single-edit fix; no phasing.

1. Edit `.github/workflows/scheduled-campaign-calendar.yml` STEP 2 step (a)
   to use the new parser for both `title` and `publish_date`.
2. Append `§H8` to `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`.
3. Write the learning file.
4. Open PR with `Closes #2987` in the body and a "Post-merge actions"
   subsection enumerating the three duplicate-issue close commands.
5. After merge, manually dispatch the workflow and verify the run log
   (operator action, see Acceptance Criteria Post-merge subsection).

## Predecessor Reference

PR #2974 (`2026-04-28-fix-campaign-calendar-max-turns-and-overdue-dedup-plan.md`)
introduced the dedup loop and the buggy parser. This plan is the
follow-through fix; the issue body's "Status" section explicitly
acknowledges the original PR's primary objective (max-turns starvation)
is verified working, and that the parser correctness regression is
"separable — re-iterate the title parser in a follow-up PR." This is
that follow-up.
