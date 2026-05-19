---
title: SHA pin prefix-match false-positive in plan-time verification
date: 2026-05-16
category: integration-issues
module: planning/review
tags: [github-actions, sha-pinning, supply-chain, plan-verification, review-cross-reconcile]
related_prs: [3893]
related_issues: [3869]
---

# Learning: SHA pin prefix-match false-positive in plan-time verification

## Problem

PR #3893 shipped a new workflow `tenant-integration.yml` whose
`DopplerHQ/cli-action` SHA pin was 37 hex chars instead of the canonical
40-char form. The truncation originated in the **plan body** (`AC9` and
`Reference Implementation` both quoted the same 37-char SHA), not in
implementation transcription, so the YAML faithfully reproduced what
the plan prescribed.

The deepen-plan phase had a "verified pins" check that ran
`git grep -l '<sha>' .github/workflows/` and reported "5 in active use"
for the DopplerHQ pin — but `git grep` matches by literal string, so
a truncated 37-char SHA appears as a hit for any 40-char SHA sharing the
same prefix. The verification was structurally weakened by the very
truncation it was meant to catch.

Three review agents (git-history-analyzer, pattern-recognition-specialist,
security-sentinel) independently flagged the truncation as P1. None of
the four other workflows that carry the canonical pin had been
re-verified character-for-character against the new file.

## Solution

Fixed inline: appended `47c` in 3 locations (1 YAML, 2 plan citations).
Verified via `git grep -hE 'DopplerHQ/cli-action@'` shows exactly one
canonical-SHA cluster and zero truncated forms.

## Key Insight

**Prefix-match-based verification is structurally blind to truncation
of the thing being verified.** Any check of the form
`git grep -l '<value>' <scope>` will silently green-light a truncated
value when the truncation is a prefix of valid full-length values in
the scope. This is the same class as "test passes both with and
without the gate" — the test/check identity depends on the value
being valid in the first place.

**Three concrete remediations:**

1. **Length-pin every SHA citation.** Plans that quote SHAs MUST also
   quote the expected length (`# v4, 40-char SHA`) so any reviewer or
   future check can byte-count without context.
2. **Verify by exact-match-and-count.** Replace `git grep -l 'sha' workflows/`
   with `git grep -hE 'uses: <action>@[0-9a-f]+' workflows/ | awk -F@ '{print $2}' | awk '{print $1}' | sort -u`
   and assert every entry has length 40. If the new pin's length differs
   from existing pins, that's the signal.
3. **Cross-reconcile triad applies to plan citations too.** When deepen
   says "5 files use pin X", a second agent should re-verify with a
   shape-aware check (length, byte-count, hash) before the verification
   is treated as evidence.

The defect class is **plan→YAML transcription of a plan-resident bug**:
the plan was authoritative AND wrong, so faithful execution
reproduced the bug. Multi-agent post-implementation review is the
backstop, but the cheaper gate is shape-checks on plan citations
before they ship.

## Session Errors

1. **PreToolUse Write hook framed as advisory but blocked first write of
   `.github/workflows/tenant-integration.yml`** — `security_reminder_hook.py`
   exit-1'd with a security reminder; the file did not materialize.
   Retry on second attempt succeeded without any code change other
   than minor commentary additions.
   **Recovery:** detected absence via `ls` check; retried with the
   same content (acknowledging the security context inline made no
   functional difference).
   **Prevention:** the hook's framing should distinguish "blocked"
   from "advisory output". The pattern `PreToolUse:Write hook error:`
   reads as a blocking error when the script's intent appears to be
   advisory. Either (a) make the hook never exit non-zero for
   advisory cases, or (b) make the heading explicit (`Security
   advisory (non-blocking):`).

2. **Step 0a.5 collision-check scans ALL `#N` refs, not just the
   target.** `#3878` was referenced only as "out of scope" context in
   the args; the strict rule would have aborted because #3878 is
   CLOSED. Required interactive escalation to proceed.
   **Recovery:** AskUserQuestion gate; user selected Continue.
   **Prevention:** restrict the closed-issue abort to refs in a
   target position (PR title, `Closes #N` patterns, primary scope
   declaration), not to every `#N` substring including "Out of
   scope" notes and cross-reference parentheticals.

3. **Plan SHA pin was truncated; deepen verification matched by
   prefix and false-passed.** Documented above as the main learning.
   **Prevention:** see "Three concrete remediations" above.

4. **yamllint pipx venv broken** — `bad interpreter: No such file or
   directory`. Environmental, not a code issue.
   **Recovery:** noted that actionlint covers structural YAML
   validation; documented in tasks.md.
   **Prevention:** environmental — operator's pipx environment needs
   repair, not a code change.

5. **Bash CWD drift between AC11 check and subsequent `git status`** —
   `cd apps/web-platform` for vitest invocation left subsequent calls
   reading paths as `../../...`.
   **Recovery:** explicit `cd <worktree-abs-path> && <cmd>` for the
   git operations.
   **Prevention:** already covered by existing rule `cq-for-local-
   verification-of-apps-doppler` and the general "Bash tool does NOT
   persist CWD" pattern. Use single-command `cd X && Y` chains for
   commands that depend on CWD.

## Tags

category: integration-issues
module: planning/review
