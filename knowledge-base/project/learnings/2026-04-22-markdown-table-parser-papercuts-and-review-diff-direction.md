---
date: 2026-04-22
category: best-practices
tags: [bash-parsing, markdown-tables, github-actions-yaml, multi-agent-review, git-diff]
issue: 2679
related_issues: [2615, 2795]
module: review + runbook-parser
---

# Learning: Markdown-table parser papercuts and review-agent diff-direction false-positives

## Problem

During implementation of PR #2795 (AEO rubric reconciliation) and its multi-agent review, four small-but-transferable papercuts surfaced. Individually trivial; together they represent a pattern worth documenting so future similar work skips these cycles.

## Four papercuts

### 1. `#` comment placed inside `prompt: |` literal block scalar

Workflow edit added a sync-sentinel `# Template-sync: ...` comment at the 12-space indent of `## Step 2: AEO Audit` — which is INSIDE the `prompt: |` multi-line scalar. The `#` became part of the prompt text sent to the agent rather than being treated as a YAML comment.

`python3 -c "import yaml; yaml.safe_load(...)"` passed (YAML syntax was valid; the file loaded fine) — the content was just in the wrong place semantically. Caught only by self-review before commit.

**Fix:** Moved the comment to YAML structural level — above `prompt: |` at the same indent as `prompt:` itself (the `with:` key level).

**Prevention:** When adding a `#` comment inside a GitHub Actions workflow, verify the line is at YAML structural indent (between keys), NOT indented inside a `|` or `>` scalar. YAML validators catch syntax errors, not semantic misplacement.

### 2. Parser stripped whitespace but not bold markdown

The `2026-04-19` re-audit runbook parser stripped only whitespace from table score cells (`"${SCORE_CELL// /}"`). Old-format audits bold the Overall row's Score cell (`| **Overall** | **72** | ...`); after whitespace-strip, `**72**` still didn't match `^[0-9]+$`, so the extractor fell through to an unsafe fallback that stripped non-digits from the *Weighted* column value `**72.0**` → `720`.

Caught only by dry-running the parser against both the 04-18 and 04-21 audit fixtures.

**Fix:** Added `${VAR//\*/}` to strip bold markers alongside the whitespace strip.

**Prevention:** When parsing markdown table cells with regex, strip inline formatting markers (`**`, `*`, backticks) in addition to whitespace before matching numeric values. The "matches valid format" check in the parser is worthless if the format can include formatting noise the strip doesn't remove.

### 3. Fallback `grep -oE '\b[0-9]{1,3}\b' | head -n 1` over full line

On new SAP Total rows with an empty Score cell (`| **Total** | 100 | | 78 | B+ |`), the fallback grabbed the first integer on the line — `100` (Weight), not `78` (Weighted).

**Fix:** Added a Weighted-column header lookup (parallel to the existing Score-column lookup) and read that column explicitly when Score is empty.

**Prevention:** When a markdown table has multiple adjacent numeric columns, anchor value extraction on header-name lookup, NOT on line-wide regex. The pattern `find column index by header name` scales; `first integer in line` does not.

### 4. Review-agent P0 false positive from Git diff-direction misuse

The `code-quality-analyst` reported a P0 "stale branch silently reverts #2796" citing files (`scripts/content-publisher.sh`, etc.) that the PR's actual diff does not touch. Root cause: the agent ran `git diff main..HEAD` (two-dot — shows commits on `main` since the fork point, NOT commits on the branch). Correct form: `git diff origin/main...HEAD` (three-dot — commits on HEAD since the merge base).

Verified by re-running with three-dot diff: 8 files, none in content-publisher. The agent's "reverts #2796" claim was an artifact of reading #2796's merge commit as if it were a branch change.

**Fix:** Reject the P0, cite the correct `origin/main...HEAD` diff.

**Prevention:** When a review agent reports unexpected large-scope regressions (claims N files changed where N is much larger than the PR's actual scope), verify immediately with `git diff origin/main...HEAD --name-only` before accepting the finding. Diff-direction is an easy mistake for agents trained on mixed Git docs — and `main..HEAD` vs `main...HEAD` produces wildly different file lists when the branch is behind main. This failure mode is NOT caught by agent rate-limiting, retries, or multi-agent consensus — only by a direct cross-check.

**Recurrence (2026-05-04, PR #3123):** Same pattern fired again 12 days later. `git-history-analyzer` reported the `feat-harness-eval-stale-rules` branch as "blocking — reintroduces a regression fixed today (PR #3142)" with a list of files (`plugins/soleur/skills/schedule/SKILL.md`, two scheduled workflows, a test guard, a learning file) that the branch's actual three-dot diff does not touch. Verified with `git diff origin/main...HEAD --name-only` — branch only modifies 9 files, none of them in the agent's claimed list. The 2026-04-22 prose-only prevention did not stick. **Escalation applied:** added a Sharp Edges section to `plugins/soleur/agents/engineering/research/git-history-analyzer.md` mandating three-dot diff at the agent-definition level. If this recurs a third time, escalate further: a `.claude/hooks/` PostToolUse hook on `Bash` that flags `git diff <ref>..HEAD` (two-dot) when the agent attribution is `git-history-analyzer`, or a wrapper script.

## Key Insight

**Bold markers, empty cells, wrong-direction diffs, and misplaced YAML comments are all the same class of bug: tools that "look valid" but apply their valid logic to the wrong data.** The signal is that the tool doesn't error — it just produces wrong output.

Defenses:

- Test parsers against fixtures from EVERY format version the parser claims to support. Don't trust mental models of "the old format should still work" — run it.
- Validate semantic placement of config/comments (is this comment at the right YAML level?), not just syntactic validity.
- Cross-check review-agent claims on Git state with the exact three-dot form before accepting large-scope findings.

## Session Errors

1. **YAML comment misplacement** — Recovery: moved above `prompt: |`. Prevention: check comment is at YAML structural indent, not inside a `|` block scalar.
2. **Bold-markdown not stripped** — Recovery: added `${VAR//\*/}`. Prevention: strip formatting markers alongside whitespace in markdown parsers.
3. **First-integer fallback grabbed Weight, not Weighted** — Recovery: Weighted-column header lookup. Prevention: header-name column index for every numeric column, never line-wide grep.
4. **Two-dot vs three-dot diff confusion** — Recovery: verified with `origin/main...HEAD`. Prevention: always use three-dot when measuring "what this PR contains"; reserve two-dot for "what changed on base since fork".
5. **Security-reminder hook false-positive on workflow Edit** — Recovery: retried identical edit, which succeeded. Prevention: the hook is advisory; first-edit-prompts-second-edit-passes is expected.
6. **`actionlint`/`npx actionlint` fabrication in initial plan** — Recovery: dropped from AC, use `yamllint` or `python3 -c "import yaml"`. Prevention: already covered by rule `cq-docs-cli-verification`.
7. **`#2615's` at line start mangled by `markdownlint --fix` into `# 2615's`** — Recovery: reworded to `The \`#2615\` exit criterion ...`. Prevention: already covered by rule`cq-prose-issue-ref-line-start`.

## References

- PR: #2795
- Issues: #2679, #2615
- Audit fixtures used for parser verification:
  - `knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md` (new SAP format)
  - `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md` (old SAP format)
- Prior learning: `knowledge-base/project/learnings/2026-04-22-agent-scorecard-determinism-requires-pinned-template.md` (captured the WHY; this one captures implementation HOW-not-to).
