---
title: Unquoted python3 heredoc that interpolates repo/corpus data is a code-injection vector
date: 2026-06-14
category: security-issues
tags: [security, code-injection, bash, heredoc, python, automation, rce, medium]
issue: "#5298"
---

# Learning: Unquoted `python3 <<PY` heredoc interpolating corpus-derived shell vars = RCE

## Problem

`scripts/followthroughs/kb-consolidation-checkpoint.sh` (run by the daily `scripts/sweep-followthroughs.sh`
automation, which executes on `main` with `GITHUB_TOKEN`) embedded the output of a metric script into a
Python heredoc with an **unquoted delimiter**:

```bash
python3 - "$BASELINE" ... <<PY
cur = json.loads(r'''$current_json''')   # $current_json shell-expanded into the heredoc body
...
PY
```

`$current_json` is JSON whose `top_pairs[].a/.b` are **filenames from `knowledge-base/project/learnings/`**
— untrusted, attacker-influenceable (anyone who lands a learning file controls its name). `json.dumps`
does not escape single quotes, and a single quote is a legal filename character. A learning named:

```
2026-01-01-a'''+__import__('os').system('id')or'''b.md
```

flows verbatim into `r'''...'''`, breaks out of the raw string, and the trailing text runs as live Python.
The focused code-reviewer reproduced end-to-end arbitrary code execution before merge.

## Solution

Pass the data through the **environment** and **quote the heredoc delimiter** (`<<'PY'`), so the shell does
no expansion of the body and Python reads inert string data:

```bash
CURRENT_JSON="$current_json" python3 - "$BASELINE" ... <<'PY'
import json, os
cur = json.loads(os.environ["CURRENT_JSON"])
...
PY
```

The sibling `scripts/kb-staleness-metric.sh` already did this correctly (`<<'PY'` + `LEARNINGS_ROOT` env) —
the bug was only in the consumer that copied the *shape* but not the *quoting*.

## Key Insight

**Any `python3 <<PY` (or `<<EOF`, unquoted) heredoc that interpolates a shell variable derived from repo
content, file names, issue bodies, or any corpus the operator does not fully control is a code-injection
vector.** The corpus is untrusted input to automation. Two safe forms:
1. Quote the delimiter (`<<'PY'`) and pass data via `ENV_VAR=... python3 ...` then `os.environ[...]`.
2. Pass data as `sys.argv` / a file path argument, never interpolated into the source text.

Grep heuristic for the foot-gun: `grep -rnE '<<[A-Z]+$' scripts/` then check each for `\$` interpolation
of non-constant data in the body. A quoted `<<'PY'` is safe; an unquoted `<<PY` with `$var` of corpus data
is not.

## Session Errors

1. **Unquoted python3 heredoc injection (RCE)** — Recovery: env var + quoted `<<'PY'` delimiter, mirroring
   the sibling metric script. — **Prevention:** never interpolate corpus/repo-derived shell vars into an
   unquoted heredoc; pass via env/argv. (This learning.)
2. **`python3 -c` quote bug** — an f-string `print(f"...{d[\"key\"]}...")` inside a *single-quoted* `-c`
   payload is a syntax error (`\"` is literal). — **Prevention:** for `python3 -c '...'`, use plain double
   quotes inside (`d["key"]`) — no escaping needed — or use `.format()`/a heredoc; one-off.
3. **Two-dot vs three-dot git diff for a "no mutation" AC** — `git diff --name-only origin/main` (two-dot)
   showed a phantom deletion of a file a sibling PR added to main after the branch point, falsely failing a
   "zero learnings changed" AC. — **Prevention:** for "changes *I* introduced" ACs, always use three-dot
   `origin/main...HEAD` (merge-base diff), never two-dot.
4. **Branch staleness** — worktree was behind `origin/main`; a sibling learning showed as a diff. Recovery:
   `git rebase origin/main` before computing baselines/ACs; one-off.

## Tags
category: security-issues
module: scripts/followthroughs
