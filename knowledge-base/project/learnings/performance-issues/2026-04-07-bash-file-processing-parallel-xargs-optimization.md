---
title: Bash File Processing Requires Parallel xargs for Large Corpora
date: 2026-04-07
module: Knowledge Base
problem_type: performance_issue
component: tooling
symptoms:
  - "INDEX.md generator took 33.6 seconds for 1,779 files"
  - "Per-file subprocess spawning (awk/grep/sed) dominated execution time"
root_cause: missing_tooling
resolution_type: optimization
severity: medium
tags: [bash, performance, xargs, parallel, file-processing, knowledge-base]
category: performance-issues
---

# Bash File Processing Requires Parallel xargs for Large Corpora

## Problem

The initial `scripts/generate-kb-index.sh` implementation spawned separate `awk`, `grep`, and `sed` subprocesses for each of 1,779 knowledge base files to extract titles from YAML frontmatter. Each file required 2-3 subprocess calls, totaling ~5,000 subprocess spawns. Execution time: 33.6 seconds — far exceeding the 5-second target for a pre-commit hook.

## Investigation

1. **First attempt:** Pure bash `while IFS= read -r line` loop per file (no subprocesses). Result: 7.3 seconds. Better but still over target. The bottleneck shifted to bash's I/O — opening 1,779 files and reading line-by-line via bash builtins is inherently slow.

2. **Checked for gawk:** `BEGINFILE`/`ENDFILE` would allow single-pass processing of all files, but gawk is not available on the system (only mawk).

## Solution

Batched parallel processing with `xargs -P4 -n100`:

```bash
printf '%s\0' "${all_files[@]}" | xargs -0 -P4 -n100 bash -c '
  KB_DIR="$1"; shift
  for f in "$@"; do
    # ... extract title using pure bash while-read loop ...
    printf "%s\t%s\n" "$rel" "$title"
  done
' _ "$KB_DIR" | LC_ALL=C sort > "$tmpfile"
```

This spawns only ~18 bash processes (1,779 files / 100 per batch), running 4 at a time. Each batch process reads ~100 files sequentially using the pure bash `while read` approach (no awk/grep subprocesses).

Result: **1.27 seconds** — 26x faster than the original, well under the 5-second target.

## Key Insight

For bash scripts processing 1,000+ files: avoid per-file subprocesses (awk/grep/sed) entirely. Use `xargs -P<cores> -n<batch>` to parallelize batches, with pure bash string operations inside each batch. The batch size (~100) amortizes process startup cost while the parallelism saturates CPU cores.

## Prevention

When writing a bash script that processes more than ~100 files, default to the `xargs -P -n` pattern from the start. The per-file subprocess approach is fine for small directories but fails catastrophically at scale.

## Session Errors

**Skill description budget exceeded (1825/1800 words)** — Adding the kb-search skill description pushed cumulative word count over the 1,800-word budget. Recovery: trimmed merge-pr and deepen-plan descriptions (removed redundant detail sentences). Prevention: before adding a new skill, check remaining budget headroom with `bun test plugins/soleur/test/components.test.ts`.

**Markdownlint converted `#$ARGUMENTS` to `# $ARGUMENTS`** — The `#$ARGUMENTS` skill template variable was interpreted as a second H1 heading (MD025). Recovery: wrapped in XML tags `<search_query> #$ARGUMENTS </search_query>` matching other skills. Prevention: when creating skills with `#$ARGUMENTS`, always wrap in XML tags per the established pattern (brainstorm, plan, deepen-plan skills).
