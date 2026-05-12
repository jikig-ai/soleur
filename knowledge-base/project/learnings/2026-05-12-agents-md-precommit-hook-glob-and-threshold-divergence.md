---
date: 2026-05-12
issue: "#3684"
pr: "#3699"
category: build-errors
module: agents-md-governance
tags: [lefthook, gobwas-glob, allowlist-parser, threshold-divergence, multi-agent-review]
related:
  - 2026-03-21-lefthook-gobwas-glob-double-star.md
  - 2026-05-12-agents-md-trim-loader-class-fit-verification.md
---

# Pre-Commit Hook for AGENTS.md Rule Budget + Anchor Parity (#3684)

## Problem

PR #3684 added two pre-commit hooks (`agents-rule-budget`, `agents-skill-enforced-anchor`) plus a shared library to consolidate the `B_ALWAYS = wc -c AGENTS.md + wc -c AGENTS.core.md` formula across three callers (compound advisory, cron post-apply revert, new pre-commit hook). Multi-agent review surfaced three sharp edges that would have shipped silently:

1. **Lefthook glob `**/SKILL.md` matched zero files** — exactly the regression class the new hook was meant to catch.
2. **Pre-commit critical threshold (22000) diverged from cron threshold (18000) without rationale** — looked like a copy-paste miss until the architecture reviewer asked which value was load-bearing.
3. **Allowlist file inline-comment misparse vector** — `plan Phase 1.4 # rationale` would have parsed as `anchor="Phase 1.4 # rationale"`, silently widening the allowlist.

## Solution

### Lefthook glob (P1)

`plugins/soleur/skills/<name>/SKILL.md` is exactly two segments under `plugins/soleur/skills/`. `**/SKILL.md` requires 1+ intermediate dirs AFTER the `**`, which would only match `plugins/soleur/skills/<name>/<sub>/SKILL.md` — zero current SKILL.md files. The fix is single-star: `*/SKILL.md`.

```yaml
# Before (silently disabled the entire gate):
- "plugins/soleur/skills/**/SKILL.md"
# After:
- "plugins/soleur/skills/*/SKILL.md"
```

Comment block above the stanza now spells out the gobwas semantics so the next contributor doesn't re-revert.

### Threshold divergence comment (P1)

The cron promoter (`scheduled-compound-promote.yml:131`) uses `MAX_ALWAYS_LOADED_BYTES=18000` as its post-apply hard cap. The pre-commit hook's critical is 22000 (warn 20000). This is intentional: cron auto-promotes unattended at scheduled cadence, so it carries the strictest budget. Fix: comment block in the workflow now documents the divergence explicitly.

### Allowlist inline-comment defense (P2)

`load_allowlist()` in `lint-agents-enforcement-tags.py` now rejects entries containing `\s#\s` with a clear remediation message: "Move the rationale to a preceding standalone `# ...` line." This closes the silent-widening vector before any future contributor exercises it.

## Key Insight

**When you wire a glob into lefthook, manually verify mindepth against the canonical `2026-03-21-lefthook-gobwas-glob-double-star.md` learning before committing.** The learning already exists. PR #3684 read the learning's path-array prescription but skipped the mindepth check, then added a new gate that silently no-op'd. The pattern-recognition reviewer caught it pre-merge — but the closer lesson is that prior-art consultation must extend past the prescription to the underlying constraint.

**When a shared library has per-caller thresholds, each caller's threshold value MUST carry an inline `# Why this caller's threshold differs:` comment.** Identical-looking constants across files invite the "did someone forget to update the second one?" question that derailed two reviewers.

**When an allowlist parser splits on first whitespace, validate that the trailing tail rejects comment-shape patterns.** Generic config-file conventions (`# inline comment`) leak into ad-hoc allowlist formats and silently widen the trust boundary.

## Session Errors

1. **lefthook.yml glob `**/SKILL.md` silently disabled new anchor-parity gate** — Recovery: change to `*/SKILL.md`. Prevention: when wiring a glob into lefthook, manually trace mindepth of the path family against `2026-03-21-lefthook-gobwas-glob-double-star.md`.
2. **Cron threshold (18000) divergent from pre-commit critical (22000) without comment** — Recovery: added explicit comment block. Prevention: shared-library callers with per-caller thresholds MUST carry a `# Why this caller's threshold differs:` comment.
3. **Allowlist file inline-comment misparse vector** — Recovery: rejected `\s#\s` patterns with a clear remediation message. Prevention: allowlist parsers that split on first whitespace must validate the tail against comment-shape patterns.

## Prevention

- Gate any new lefthook glob through the `2026-03-21-lefthook-gobwas-glob-double-star.md` mindepth check at plan time, not at review time.
- When introducing a shared formula library with per-caller thresholds, encode the rationale for the divergent threshold in a comment at the call site, not in a separate doc.
- Allowlist parsers should reject inline-comment shapes by default — operators expect `#` to mean "comment" universally.
