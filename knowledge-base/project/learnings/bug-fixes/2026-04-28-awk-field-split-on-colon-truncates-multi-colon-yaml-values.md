---
date: 2026-04-28
category: bug-fixes
module: ci-workflows
component: github-actions
problem_type: logic_error
root_cause: parser_misuse
resolution_type: code_fix
severity: medium
issue: 2987
pr: 2995
symptoms:
  - "campaign-calendar dedup search files duplicates against existing open audits"
  - "Issue titles truncated at first inner colon (e.g., 'Show HN: ...' → 'Show HN')"
  - "Issue titles carry a trailing quote artifact ('Browsers\"' instead of 'Browsers')"
tags: [awk, mawk, github-actions, yaml, frontmatter, dedup, campaign-calendar]
related:
  - knowledge-base/project/learnings/2026-03-31-awk-split-defaults-to-fs-not-whitespace.md
  - knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md
  - knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md
  - AGENTS.md#cq-workflow-pattern-duplication-bug-propagation
  - AGENTS.md#wg-when-fixing-a-workflow-gates-detection
---

# Troubleshooting: `awk -F': '` Truncates Multi-Colon YAML Values; `sub(/^X|X$/)` Only Fires Once

## Problem

The `scheduled-campaign-calendar.yml` STEP 2 dedup loop reads a file's `title` and `publish_date` frontmatter via inline awk, then searches for an existing GitHub issue with that title. Two compounding bugs in the parser made the dedup search miss every multi-colon-bearing or quote-wrapped title:

1. **`awk -F': '` field-split truncates at the first inner `: `.** A YAML title like `title: "Show HN: Soleur — open-source agents that call APIs, not browsers"` parses with three fields: `title`, `"Show HN`, `Soleur — …"`. Printing `$2` emits `Show HN` (after the leading-quote strip).
2. **`sub(/^"|"$/, "", $2)` strips only ONE quote.** POSIX `sub()` replaces the FIRST regex match. Alternation `^"|"$` matches left-anchored `"` first; the trailing `"` survives. `Agents That Use APIs, Not Browsers"` reaches the dedup search with a literal trailing quote that no canonical existing-issue title contains.

The two bugs sit on the same code path. Run 25043177327 (2026-04-28) filed `#2982/#2983/#2984` against still-open canonical audits `#2146/#2969/#2970`.

## Environment

- Module: CI Workflows
- Affected Component: `.github/workflows/scheduled-campaign-calendar.yml` STEP 2 step (a)
- Runtime: `mawk 1.3.4` (GHA `ubuntu-latest` default), behavior is identical on `gawk` and BSD `nawk`
- Predecessor PR: #2974 (introduced the dedup logic with the buggy parser)

## Root Cause

`awk -F'X'` is **not** a parser for any structured format where `X` may legitimately appear inside values. YAML uses `: ` as the key/value separator only at the FIRST occurrence on a line; everything after is the value. The FS-based approach forces awk to treat `: ` as a field delimiter wherever it appears, which is correct for two-column delimited data but wrong for "extract everything after the prefix."

The second bug is a common bash-idiom misread: `sub(regex, replacement, target)` in POSIX awk replaces the FIRST match. Regex alternation does not change this — the engine selects the leftmost-longest alternative and replaces it once. Strip-both-ends needs TWO `sub()` calls.

This is the same root family as the 2026-03-31 learning (`2026-03-31-awk-split-defaults-to-fs-not-whitespace.md`): awk's field-extraction primitives default to FS, and FS is almost always wrong for structured text. The fix in both cases is to bypass FS — use `match() + substr()` for prefix extraction, or pass an explicit delimiter to `split()`.

## Symptoms

- `gh issue list --search "\"<canonical-title>\" in:title"` returns no match for any title containing an inner `: `.
- New issues get filed with truncated titles or trailing-quote artifacts.
- Existing canonical audits (e.g., #2146, #2969, #2970) remain open in parallel — DEDUP counter never increments for those slots.
- Watchdog signal degrades: real overdue items are buried under operator backlog noise.

## Resolution

Replace the FS-based parser with a `match() + substr()` form and use TWO `sub()` calls per quote style:

```bash
TITLE_RAW=$(awk 'match($0, /^title: ?/) {
  s = substr($0, RLENGTH + 1)
  sub(/^"/, "", s); sub(/"$/, "", s)
  sub(/^'\''/, "", s); sub(/'\''$/, "", s)
  print s; exit
}' "$FILE")
```

Why this form is correct:

- `match($0, /^title: ?/)` matches the prefix only at line start; sets `RLENGTH` to the matched-prefix length (POSIX).
- `substr($0, RLENGTH + 1)` returns the full remainder of the line — preserves every inner `: ` because we never split on `: ` at all.
- Two `sub()` calls per quote style strip leading and trailing wrappers independently.
- `match()` and `substr()` are POSIX awk and ship in every awk implementation; no `gensub()` or `RT` (gawk-only) features are used.

Apply the same fix to `publish_date` in the same edit, per `cq-workflow-pattern-duplication-bug-propagation` — the sibling field uses the identical buggy idiom and parses correctly today only by accident (no current dates contain `: `).

## Verified Alternatives

The `scripts/content-publisher.sh` `get_frontmatter_field()` pattern is functionally equivalent and uses sed:

```bash
parse_frontmatter | grep "^${field}:" | sed "s/^${field}: *//" | sed 's/^"\(.*\)"$/\1/'
```

The greedy `\(.*\)` capture group preserves multi-colon values. This works for shell scripts but is awkward to source from a GHA prompt-driven shell.

## Rejected Alternatives

- **`yq '.title' "$FILE"`** — robust YAML parsing, but adds a runner dependency. `ubuntu-latest` ships `yq` v4 pre-installed today, but no workflow currently sets it up explicitly. Pure-awk is simpler and zero-dependency.
- **Inline Python via `python3 -c "import yaml; ..."`** — `pyyaml` is not in the stdlib; would need a `pip install` step. Heavyweight for a 2-line awk fix.
- **Source `scripts/content-publisher.sh`** — the action runs in a fresh prompt-driven shell; sourcing a 200-line script for two field reads is overkill. Consolidate IF a third workflow needs the same parser.

## Limitations

The `match() + substr()` form does NOT handle:

- **YAML block scalars** (`title: >-` followed by a folded value on the next line). The parser would emit the empty remainder of the `title:` line.
- **Multi-line quoted strings.** Single-line awk only sees one record at a time.

The current corpus uses neither; if a future content file adopts block scalars, the parser must be revisited. The runbook §H8 entry documents the limitation.

## References

- Issue: [#2987](https://github.com/jikig-ai/soleur/issues/2987)
- Predecessor PR: [#2974](https://github.com/jikig-ai/soleur/pull/2974) (introduced the dedup loop and the buggy parser)
- Sibling learning: `knowledge-base/project/learnings/2026-03-31-awk-split-defaults-to-fs-not-whitespace.md`
- Canonical sed parser: `scripts/content-publisher.sh` (`get_frontmatter_field`)
- Runbook entry: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` §H8
- AGENTS.md rules applied: `cq-workflow-pattern-duplication-bug-propagation`, `wg-when-fixing-a-workflow-gates-detection`
