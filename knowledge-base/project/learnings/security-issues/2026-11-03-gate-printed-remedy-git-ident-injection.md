---
module: Soleur hooks (cla-signed-author-gate)
date: 2026-11-03
problem_type: security_issue
component: tooling
symptoms:
  - "the gate's deny message prints an executable `git filter-branch --env-filter` remedy that interpolates offender %ae/%ce emails"
  - "git ident sanitization does NOT strip $(...), backticks, quotes, or ';' — they land in %ae verbatim (measured: `-c user.email='evil$(touch /tmp/PWNED_MARK);`id`@x.com'` round-trips through %ae unchanged)"
  - "a crafted author/committer email could therefore execute when filter-branch sh -c's the printed env-filter, or break the printed single-quote at paste time"
root_cause: missing_validation
resolution_type: code_fix
severity: high
rule_id: wg-cla-signed-author-before-merge
issue: 12027
status: closed
tags: [command-injection, git-ident, filter-branch, hook-remedy, paste-injection, cla-gate, untrusted-interpolation]
---

# Troubleshooting: a gate's printed executable remedy is a paste-able injection surface when it interpolates raw git ident bytes

## Problem

`.claude/hooks/cla-signed-author-gate.sh` (stage 2, #12027) denies `gh pr ready` /
`gh pr merge` when a branch commit's author/committer email is outside the
CLA-sanctioned set, and prints an executable `filter-branch --env-filter` remedy
naming each offender. Commit author/committer identity bytes are
attacker-influenceable — anyone who can push a commit shapes `%ae`/`%ce`. Git's
ident sanitization (measured 2026-11-03) strips only newline/NUL-class bytes and
trims surrounding `<>`/whitespace; `$(...)`, backticks, single/double quotes and
`;` are stored **verbatim** and come back through `git log --format=%ae` intact.

That makes the printed remedy two injection routes at once:

1. The remedy emits offenders as double-quoted `for e in "…"` args **inside** the
   single-quoted env-filter. `$(...)` and backticks inside double quotes execute
   when `filter-branch` runs the env-filter via `sh -c` per commit — no quote
   escape needed.
2. A `'` inside an offender email terminates the printed single-quoted
   env-filter outright, turning the tail into live shell at paste time.

## Environment

- Module: `.claude/hooks/cla-signed-author-gate.sh` (PreToolUse Bash hook)
- Date: 2026-11-03
- Verification: `git -c user.email='evil$(touch /tmp/PWNED_MARK);`id`@x.com' commit`
  in a scratch repo → `git log --format=%ae` returns the string byte-for-byte.

## What Didn't Work

**Trusting git to sanitize.** `%ae` output is raw storage bytes, not a safe
token — the sanitizer's contract is "parseable ident", not "safe for shell".

**Emitting offenders inside a `case` glob.** `[bot]` in a case pattern is a
bracket expression, not literal text — glob contexts mangle bot emails in the
other direction. The remedy uses a quoted literal `for e in` list, not
glob/case-pattern interpolation.

## Solution

Charset-validate every offender email **before** it can appear inside quotes in
an executable remedy. Conforming emails become `for e in` args; anything else is
reported as a sanitized manual-rewrite line and never reaches an executable
position:

```bash
# Remedy-arg validation — only RFC-5322-ish shapes are emitted as args
if [[ "$_e" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
  _fix_email_args+="\"${_e}\" "
else
  _fix_manual+="manual rewrite required for: $(printf '%s\n' "$_e" | soleur_ctx_sanitize_lines)"$'\n'
fi
```

If every offender fails validation the remedy degrades honestly:
`(no executable remedy — every offending email failed charset validation; see the
manual-rewrite list)` instead of printing a weaponized command.

## Why This Works

The deny message is a **command surface**: the operator is expected to paste it.
Any field that flows into it from VCS metadata is untrusted input into a string
that will be executed. Whitelisting the charset (rather than blacklisting
metacharacters) is robust by construction — a charset that cannot express `'`,
`"`, `$`, backtick or `;` cannot break any quoting context the remedy uses, and
no escaping logic has to be proven correct against future remedy shapes.

## Prevention

- Any hook/gate/skill that prints an **executable** remedy must charset-validate
  attacker-influenceable interpolations, or emit them only inside a sanitized
  non-executable instruction. Ask "could a commit/push shape this field?" — `%ae`,
  `%ce`, `%an`, `%cn`, ref names, subjects all qualify.
- Prefer whitelists: `^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$` for emails. A blacklist
  of metacharacters must be complete for every quoting context the string passes
  through — paste-time shell AND the filter-branch `sh -c`.
- A fallback line ("manual rewrite required for: <sanitized>") preserves the
  deny's usefulness when validation rejects an offender, rather than hiding it.
- Test arm in `cla-signed-author-gate.test.sh` plants a metachar-laden email and
  asserts it appears only in the manual-rewrite list, never as a `for e in` arg.

## Session Errors

**`git branch --show-current` ran in a fresh shell at the bare repo root and reported `main` (plan phase, forwarded in session-state.md).**

- **Recovery:** re-ran with explicit `workdir` — the worktree was correctly on the feature branch; all later commands used explicit `-C`/`workdir`.
- **Prevention:** in a worktree session never trust a bare `git branch --show-current` in a fresh shell — pin `-C <worktree>` (already covered by `hr-when-in-a-worktree-never-read-from-bare`).

**`markdownlint` prints usage text when pointed at plan files (plan phase, forwarded).**

- **Recovery:** confirmed `knowledge-base/project/` is exempt by `.markdownlintignore` (#7927 design) — no lint applies there; continued.
- **Prevention:** check `.markdownlintignore` before treating a linter's usage output as a finding on KB paths.

**Pipeline brief's premise — "`devin-ai-integration[bot]` is a sanctioned override per git-rules" — was measured FALSE (plan phase, forwarded).**

- **Recovery:** recorded as `pending - assumed` rows in `decision-challenges.md`; the CTO consult ruled EXCLUDE after measuring `origin/main:.github/workflows/cla.yml` allowlist, `origin/cla-signatures:signatures/cla.json`, and PR #11690's red cla-check.
- **Prevention:** an issue/brief premise that reads as established ("sanctioned carve-out") still needs a measured falsification command — `git show origin/main:.github/workflows/cla.yml | grep <bot>` refuted this one in seconds.

**deepen-plan Phase 4.7 authored a `discoverability_test.command` shaped like the whole suite (`.test.sh`) (plan phase, forwarded).**

- **Recovery:** corrected to `grep SANCTIONED .claude/hooks/cla-signed-author-gate.sh` — a probe of the new marker, not the suite.
- **Prevention:** author discoverability probes as a grep of the diff's new constant/marker; a suite-shaped probe re-runs everything and halts on cost.

**Compound session: scratch-repo verification `git commit` denied twice by hooks (variable path, then not-yet-existing path in the same command).**

- **Recovery:** created `/tmp/ident-test-12027` as its own call, then ran `git -c user.email=… commit` against the literal path — hook working as intended.
- **Prevention:** the commit-scanning hook resolves only literal absolute paths that already exist — create the dir first, then commit with the literal path.

## Related Issues

- See also: `../workflow-patterns/2026-06-04-subagent-commits-fail-cla-check.md` (the original gate and the PR #4948 cla-check failure)
- See also: `../integration-issues/2026-10-30-npm-e404-is-authz-masking-and-devin-commits-break-cla-check.md` (measured evidence that `devin-ai-integration[bot]` fails cla-check)
- See also: `../best-practices/2026-11-03-cla-sanctioned-set-gate-design.md` (the sanctioned-set design this remedy belongs to)
- Issue: #12027; related: #7218, #11690
