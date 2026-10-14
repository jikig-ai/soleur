---
title: The guard's own normalizer is attack surface — text preprocessing that *removes* content is fail-open, and a carve-out must only exempt dialects the delegated census can actually see
date: 2026-10-12
category: engineering
tags: [guard-machinery, mutation-battery, terraform, ssh-residence, fix-round]
issue: '#9998'
pr: '#10130'
type: learning
---

# Learning: the guard's own normalizer is attack surface — text preprocessing that *removes* content is fail-open, and a carve-out must only exempt dialects the delegated census can actually see

## Problem

#9998: Guard 2's SSH residence check was web-2-only (a `w2_elsewhere` arm); web-1 and future `web-N`
connection blocks outside `server.tf` were unclassified. Replacing it with a fleet-symmetric arm needed
span-bounded resource attribution, an `(file, type.name, hosts, reason)`-scoped `EXT_RESIDENCE`
allowance table, and — the expensive discovery — the guard's *scanner helpers themselves* kept opening
holes faster than the arms could close them.

## Solution

- `blank_heredocs` runs **before** `strip_hcl`, comment/string-aware, and blanks heredoc bodies to
  newline-preserving spaces: `{`/`}`/`"`/comment-text inside heredocs stops corrupting brace spans,
  `in_str` state, and header regexes in one move.
- Attribution is span-containment, not nearest-header: `res_spans` (capped at the next top-level
  construct), `nonres_spans` (any non-resource construct containing a `resource` header → drop **and**
  report), `dup_addrs` (same `(dir, type.name)` = finding), top-level keyword enum single-sourced.
- The `server.tf` carve-out delegates to §1's census — so it only exempts blocks **§1 can see**:
  `terraform_data.*` + literal `connection {}` + literal `type = "ssh"` token. Dynamic-spelled,
  winrm-typed, and type-less dials inside server.tf are flagged.
- Mutation battery grew 13→17 #9998 rows (G2-19..37) + 2 green controls; `FLOOR` re-derived to exact
  census (95) so silently-deleted rows always trip it.

## Key Insight

Every preprocessing step in a text-guard has a **failure direction**: steps that *delete* content
(comment stripping, body blanking, span caps) are fail-open when they're wrong — they erase evidence
and the guard stays green. Two review seats independently demonstrated the same exploit: a `<<TAG`
inside a `#` comment paired with a later bare `TAG` terminator blanked a smuggled resource into spaces.
The mirror-image rule: when an arm *exempts* by delegating to another enumeration (§1's census), the
exemption must be provably **inside that enumeration's dialect** — a wider sweep plus a narrower
delegated census is a guaranteed classification hole between the two grammars. And a span *cap* is the
safe default because truncation costs attribution (fail-closed); a span *extension* grants it
(fail-open). Battery-row every mechanism claim — five of this PR's thirteen review-found holes were
"obvious" until a seat ran them.

## Session Errors

1. **`expect_red` extra-needle arg placed before the script — twice.** Needles trail the mutator;
   a needle string in the script slot produced `mutator errored`. **Prevention:** `apply_mutation` now
   `ast.parse`-checks the script before the battery cycle; fail-fast and named.
2. **First non-resource span regex over-matched on the real tree** — `locals` in
   `betterstack-logs-alerts.tf` spanned to line 1073 (SQL heredoc braces counted). **Prevention:**
   blank heredoc bodies before ANY braced-span machinery, and always run the real tree before the
   battery — the battery's synthesized files can look cleaner than the corpus.
3. **`blank_heredocs` initially ran after `strip_hcl`.** An odd `"` count inside the SQL heredoc
   flipped `strip_hcl`'s `in_str` and silently ate real code — the quote-flip corruption the helper
   existed to prevent. **Prevention:** normalization passes that protect a downstream pass must run
   first; document ordering invariants in the caller, not just the helper.
4. **Span cap made G2-25 go green at the boundary.** The drop predicate used capped ends; the fake
   header landed exactly at the cap. **Prevention:** keep capped and uncapped span ends as separate
   data; use the true end for identity checks and the cap only for attribution.
5. **`is_ssh_conn` defined inside the loop it served.** Hoisted. **Prevention:** helpers close over
   nothing — put them with the sibling helpers.
6. **`test-all.sh --affected` queued ~2h behind the repo-global lock**; a `timeout`-killed earlier run
   left stale child pids counted as sibling runs. **Prevention:** kill the whole process group when
   timing out a runner (`timeout` on the wrapper doesn't reap children); check `--capacity` before
   believing a long wait is a hang.
7. **`pipeline-tally.sh print` → bad-flag** (the subcommand is `show`); **`fix-round-seats.sh` rejects
   space-separated `--finding-seats`** (needs commas). **Prevention:** `--help` before first use of
   tally/fix-round scripts; both are fail-open stubs.
8. **session-state.md lagged its own tree twice** (recorded 109/FLOOR-71 while the tree was
   111/FLOOR-73). **Prevention:** re-sync spec docs in the same commit as the code they describe, or
   the history seat will report the drift as a finding.

## Errors forwarded (plan phase)

9. **Planning subagent had no Task/Agent tool** — every prescribed sub-spawn (research fan-out,
   advisors, plan-review panel) ran inline instead. **Prevention:** none needed at session level —
   the plan's Enhancement Summary discloses the substitution; recorded here for completeness.
