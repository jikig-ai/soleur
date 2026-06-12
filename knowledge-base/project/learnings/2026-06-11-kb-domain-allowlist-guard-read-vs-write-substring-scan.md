# Learning: a write-detection guard built on a first-match substring scan keeps producing read-vs-write false positives

## Problem

`.claude/hooks/kb-domain-allowlist-guard.sh` is a PreToolUse advisory guard that fires `ask`
when a Bash command would create a NEW top-level entry under `knowledge-base/` outside the
sanctioned domain set. It detected the kb path with a **first-match substring scan** over the
entire command string (`[[ "$TARGET" =~ knowledge-base/([^/[:space:]\"\']+) ]]`).

That scan cannot tell a *read reference* from a *write target*. Read-only commands that merely
MENTION a kb path tripped the advisory and forced the operator to manually approve harmless
reads. The reported repro:

```
git show main:knowledge-base/.gitkeep >/dev/null 2>&1 && ...
```

matched `knowledge-base/.gitkeep` inside a git `<ref>:<path>` object read → `SEGMENT=.gitkeep`
→ unsanctioned, no glob metachars, not a real on-disk file → spurious `ask`.

This is the **second** false-positive patch to the same hook. The first (lines 84-86 glob-guard)
patched a sibling case: a `grep`/comment pattern like `knowledge-base/*.md` landing as the
first match instead of the real `git add` write. Same root shape: the scan finds A path-looking
substring, not THE write target.

## Solution

For the **Bash class only**, gate the advisory on actual write-intent — a positive
write-VERB / kb-targeted-REDIRECT allowlist — placed after segment extraction, before the
older glob-guard:

```bash
KB_WRITE_VERB_RE=$'(mkdir|touch|tee|sed[[:space:]]+-i|cp|mv|install|ln|rsync|git[[:space:]]+add|git[[:space:]]+mv|git[[:space:]]+rm)[^|;&\n]*knowledge-base/'
KB_WRITE_REDIR_RE='>>?[[:space:]]*"?'"'"'?knowledge-base/'
if [[ -n "$IS_BASH" ]] && [[ ! "$TARGET" =~ $KB_WRITE_VERB_RE ]] && [[ ! "$TARGET" =~ $KB_WRITE_REDIR_RE ]]; then
  exit 0   # read-only kb reference → pass-through
fi
```

Key details that bit during implementation/review:
- The redirect regex MUST anchor the literal `knowledge-base/` right after `>`/spaces/quote,
  so `>/dev/null 2>&1` (present in the repro) does NOT match. A naive `>`-presence check
  re-introduces the bug.
- `[^|;&\n]*` bounds the verb→path span to ONE pipeline/command segment **including across
  lines** — the newline must be in the exclusion class (use `$'...'` so `\n` is a literal
  newline) or a stage-1 verb reaches a later-LINE kb read. (Caught at review; the inline
  comment claimed segment-bounding the regex didn't fully provide.)
- Both regexes MUST be assigned to variables before `[[ =~ ]]` — an inline literal containing
  `;`/`&`/`|` is a bash conditional-expression parse error.
- `IS_BASH` discriminates fail-open: `tool_name=="Bash"` OR (`tool_name` empty AND `command`
  present AND `file_path`/`notebook_path` absent), mirroring `background-poll-prefer-monitor.sh:81`.
  File tools keep current behavior (their `file_path` is an unambiguous write target).

## Key Insight

A guard whose JOB is "catch writes" but whose MECHANISM is "find any path-looking substring"
will keep generating read-vs-write false positives — each new read idiom (`git show ref:path`,
`grep pattern`, `git ls-tree`, `cat`) is a fresh variant. The durable fix is to detect
**write intent positively** (verbs + redirects whose target is the path), not to keep
blacklisting read shapes. This aligns with the guard's stated philosophy: it exists for
*accidental taxonomy drift*, not adversarial-evasion defeat, so a short positive allowlist that
errs toward extra advisory asks (never silent misses, never a deny) is the correct precision/safety
tradeoff. Anchoring the short verbs (`cp`/`mv`/`ln`) was deliberately NOT done: anchoring risks
converting a caught write (`;mkdir ...`) into a missed write, and an extra advisory ask is the
safe failure direction.

## Session Errors

- **Edit-before-Read across a skill boundary** — the first `Edit` to the hook header inside the
  `/soleur:work` context failed ("File has not been read yet") although the file had been Read
  at the top of the `/soleur:go` turn. **Recovery:** re-Read the file in-context, then the edit
  succeeded. **Prevention:** when a pipeline reads a file in a parent skill and a child skill
  then edits it, re-Read it first in the child context. One-off in effect — the tool enforces
  the correct behavior and recovery is automatic; no rule gap.

## Tags
category: integration-issues
module: claude-hooks
related: kb-domain-allowlist-guard.sh, no-memory-write.sh
