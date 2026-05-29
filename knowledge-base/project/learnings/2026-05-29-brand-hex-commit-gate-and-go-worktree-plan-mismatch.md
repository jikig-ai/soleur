---
title: "Commit-time brand-hex gate design + /soleur:go worktree-plan-vs-issue mismatch"
date: 2026-05-29
category: workflow-patterns
tags: [hooks, pretooluse, brand, frontend-anti-slop, soleur-go, worktree, ugrep, regex]
issue: 4644
pr: feat-brand-hex-commit-gate
---

# Commit-time brand-hex PreToolUse gate (#4644) + a `/soleur:go` routing gap

## Problem

Two distinct things this session:

1. **Feature:** off-brand colour (`#2563eb`) shipped in the invite UI and
   transactional emails (#4631/#4639) with no gate catching it — the only
   brand-adjacent check, `frontend-anti-slop`, is advisory and review-time, so
   it is silently skippable. #4644 asked for the *un-bypassable* layer: a
   commit-time PreToolUse hook.

2. **Workflow gap:** `/soleur:go #4644` → "Continue in that worktree" was
   offered for `feat-one-shot-brand-hex-scanner-gate`, a worktree whose only
   planning artifact targeted the **sibling** issue #4635 (the scanner
   quick-wins), not #4644. The router matched the worktree *name* topically
   ("brand-hex") but not the *issue* the worktree's plan actually targets.

## Solution

### The gate (`.claude/hooks/brand-hex-commit-gate.sh`)

Modelled on `git-commit-secret-scan.sh`. Key design decisions, each non-obvious:

- **JSON `permissionDecision: deny` (exit 0), not the issue's literal "exit 2".**
  Every sibling Bash PreToolUse gate in `.claude/settings.json` uses the
  JSON-decision shape and the hook test harness keys on it. Following the repo
  convention beat following the issue's wording.
- **Scan *added* lines, not whole files.** Catches the incident class (new
  off-brand hex) without surprise-blocking unrelated edits to legacy files
  (8 component + 14 email pre-existing hits). The full-file forward-sweep is
  the review-time scanner's job (#4635). Respects the non-technical-solo-founder
  user model (`hr-weigh-every-decision-against-target-user-impact`).
- **Two enforcement modes.** Components/pages/docs → *any* raw hex blocked (must
  use a token). Email/server templates → literal hex allowed **only if in the
  discovered brand palette** (off-brand blocked); this is the "path-scoped
  literal-hex exception" reading that makes both halves of the issue text
  ("scan server/*notification*" AND "emails use the exception") coherent and
  closes the off-brand-email half of the incident. Token-definition CSS exempt.
- **Palette + token-definition files discovered from the project's own CSS**
  (any `.css` declaring `--name: #hex`), so the gate generalises to each
  project's brand; path classes overridable via `SOLEUR_BRAND_HEX_UI_RE` /
  `_EMAIL_RE`.

### Review-driven fixes (all pr-introduced → fixed inline, 0 scope-outs)

- **Palette must be read from the committed tree, not the worktree.** Building
  the palette from `cat $f` let an *unstaged* `--x: #offbrand` token edit
  whitelist off-brand email hex. Fixed: `git show ":$f"` (index) for normal
  commits; worktree only for `git commit -a` (where the worktree IS committed).
- **`-a`/`--all` detection must strip the commit message first.** `git commit
  -m "fix -a flag"` matched the `-a` flag-detector and flipped the diff base to
  HEAD → false deny when the worktree had unrelated unstaged off-brand edits.
  Fixed: `sed` away quoted argument values before the flag grep.
- **Regex breadth vs. false-positives.** security-sentinel proposed full
  fail-closed inversion (flag every `#hex`, exempt `href`/`url(`/`id`). Rejected
  — it false-positives on `fill="url(#gradientId)"` SVG paint refs. Instead used
  4 anchored shapes: Tailwind `[#hex]{3,8}`; url-*safe* props (color/border/
  shadows) hex-*anywhere* in the value (`border: 1px solid #hex`); url-*prone*
  props (background/fill/stroke) hex *directly* after the separator (so
  `url(#ref)` is not matched); gradient functions. Low-FP, catches the verified
  misses.

## Key Insight

For a commit-time brand gate, **read the palette from what is being committed,
not the dirty worktree** (else the allowlist is attacker/accident-controlled),
and **anchor the colour regex on colour-relevant tokens** rather than matching
all hex (the `url(#id)` SVG-ref false-positive is the trap that makes naïve
fail-closed worse than targeted detection). `git diff -z | mapfile -d ''` —
never `grep -z` — because the host grep is ugrep 7.5.0 where `-z` is
`--decompress` (the same root cause as #4635's no-op).

## Session Errors

1. **`/soleur:go` "Continue in that worktree" routed an issue into a
   sibling-issue's worktree.** #4644 was routed to a worktree whose only plan
   targeted #4635. — Recovery: surfaced the mismatch, asked the user, created a
   fresh `feat-brand-hex-commit-gate` worktree. — **Prevention:** the go-skill's
   "Continue in that worktree" path should check whether the worktree's planning
   artifact (`knowledge-base/project/plans/*`) references the SAME issue number
   as the input, not just whether the worktree name is topically related. Added
   as a Sharp Edge to the `go` skill.

2. **`local` used outside a function in the hook body.** Wrote `local tok=` in
   the main scan loop (bash errors on `local` outside a function). — Recovery:
   renamed to a plain `tok=` before the first test run; caught by reading the
   code. — **Prevention:** run `shellcheck` on a new hook *before* the first
   execution, not only after GREEN — SC2168 flags `local`-outside-function
   deterministically.
