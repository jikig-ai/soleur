# Learning: a `#` line inside a backslash-continuation splits the command in two — and the fold that checks the file still reads one logical line

## Problem

PR #11735 (closes #11553 — pin `&sort=-timestamp` on statsPeriod-only Sentry `/events/`
probes + lint rule 6) placed an explanatory comment INSIDE a `curl` line-continuation
block:

```bash
SC=$(curl ... -G \
  --data-urlencode 'field=count()' \
  --data-urlencode 'query=...' \
  # Ordering pin exempt (lint rule 6): field=count() is a one-row aggregate
  --data-urlencode 'statsPeriod=48h' \
  --config - "https://.../events/" ... | jq ... || echo "")
```

Backslash-newline removal happens BEFORE tokenization, so the joined logical line is
`... 'query=...'   # Ordering pin exempt ...` — the `#` starts a comment and the whole
continuation dies there. What remains is:

1. `curl ... --data-urlencode 'query=...'` — no URL, exits 2.
2. `--data-urlencode 'statsPeriod=48h' --config - "https://..." | jq ... || echo ""` —
   a fresh command whose NAME is `--data-urlencode` → 127, swallowed by `|| echo ""`.

Net effect: `SC=""` every run; the Sentry cross-check the block exists to perform
silently reported "inconclusive" forever — a dead check wearing a passing costume.
`bash -n` sees nothing (comment lines are legal syntax). The suite WOULD have caught it
(the `curl keeps --disable first and reads --config -` argv row greps the stub's argv
for `--config -`, which the split command never reaches) — but the work phase had
deferred that file's suite run to a later phase. The catch was shellcheck's SC2215
("flag used as a command name — bad line break?"), run as the review skill's bash-only
substitute for semgrep-sast.

## Solution

- Hoisted the comment above the `SC=$(curl` line (fix commit `ac3361b1a4`).
- Documented BOTH directions of the asymmetry in `lint-followthrough-varq-ban.sh` rule
  6's DECLARED BLIND SPOTS:
  - lint drops `#` lines BEFORE folding; bash ends a continuation AT a `#` line — the
    comment splits the command while the lint still reads one logical line;
  - the dual false-satisfier: an INLINE `# ... sort= ...` comment meets the bound
    predicate while the call carries no bound (mid-line comment-stripping needs
    quote-awareness the fold does not have — declared, not checked).
- Added suite row R6-M5 pinning the bound predicate's non-identifier left edge
  (`resort=`, `xstart=`/`xend=`, `append=` all fail to satisfy) — the header claimed
  the edge with no fixture behind it.

## Key Insight

**Two fold models, one file.** Bash folds `\`-continuations INCLUDING comment lines
(a `#` kills the joined line); a comment-aware lint folds AFTER dropping comments. Any
checker whose "logical line" ≠ the interpreter's has a blind spot in BOTH directions —
it sees commands that don't exist and misses splits that do. When a guard documents
"comments are dropped before folding", ask which side the interpreter is on.

Companion lessons:

- A fix's own comment is the least-audited surface — this defect was authored by the
  PR fixing the class it belongs to (the exemption note itself broke the exempted call).
- `bash -n` is a syntax gate, not a semantics gate; on bash-only diffs shellcheck is the
  check that sees command-splitting (SC2215). The repo has no shellcheck CI gate —
  run it on every `.sh` hunk by hand (the review skill's substitution already does).
- Deferring a touched file's own suite to a later pipeline phase leaves the window in
  which this defect lived. Run the file's suite with the edit, not after the edit batch.
- Zero-incidence classes don't earn a new rule: a repo-wide scan (`#`-only line after a
  `\`-line) found this one instance and no others — the fix is documentation at the
  fold model, not a seventh lint arm.

## Session Errors

1. **Exemption comment authored inside a `\`-continuation** (work phase, caught in
   review). Recovery: hoisted above the command (`ac3361b1a4`) and the file's suite
   re-run green. **Prevention:** rule-6 header now names both fold-model asymmetries;
   on bash-only diffs run `shellcheck -S warning` on every touched hunk — SC2215 is
   the diagnostic for this class.
2. **The edited file's own suite deferred to a later phase** (tasks.md §Deviation ran
   `lint-followthrough-varq-ban.test.sh` + live lint but deferred
   `anthropic-admin-key-6297.test.sh` — the file carrying the defect). Recovery:
   ran at review time; it caught nothing retroactively because the fix landed first,
   but the argv-shape rows are load-bearing for this class. **Prevention:** when a
   task list delegates a suite run to a later phase, re-check it against the file list
   actually edited — a suite named "run later" is the suite the defect needed now.
3. **`get_output` called with a `command` field** (this session; rejected as invalid
   input). One-off tool-shape slip; no workflow change.

## Tags

category: test-failures
module: scripts/followthroughs, scripts/lint-followthrough-varq-ban.sh
refs: #11553, PR #11735, PR #11543 (CTO ruling), shellcheck SC2215
related: knowledge-base/project/learnings/2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md
