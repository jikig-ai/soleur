---
date: 2026-06-02
category: best-practices
component: content-authoring
tags: [acceptance-criteria, grep-verification, marketing-copy, multi-register, false-positive]
issue: 1445
pr: 4775
---

# Grep/wc-based ACs over a multi-register document must scope to the asserting subsection

## Problem

Authoring `knowledge-base/marketing/recruitment-messaging-templates.md` (one recruitment
template per channel, two voice registers) the plan's acceptance criteria were grep/wc
checks. Two of them are false-positive traps when run document-wide:

- **AC4 (prohibited-term compliance):** "No General-register section uses `plugin`,
  `Claude Code`, `copilot`, `assistant`, `AI-powered`, `just`, `simply`, `terminal-first`."
  A document-wide grep flags the file's own **`## Proof-point discipline`** meta-section,
  which legitimately *enumerates the forbidden terms* ("no 'plugin', 'Claude Code', …").
  The meta-guidance contains the very strings the AC forbids in body copy.
- **AC9 (X/Twitter ≤280 chars/post):** a `sed -n '<range>p'` that overshoots the X/Twitter
  section also captures the **Direct-network email** block, whose paragraphs legitimately
  exceed 280 chars (email ≠ tweet). The over-broad range produced a spurious `OVER 346`.

## Solution

Scope every grep/wc AC to the **subsection that the AC actually asserts over**, not the
whole file:

1. Enumerate section boundaries first: `grep -nE '^(## |### )' "$F"`.
2. For prohibited-term / pattern-forbidden ACs, run the grep only over the *body-copy*
   line ranges of the asserting register (`sed -n '95,146p' | grep -inE '\b(...)\b'`),
   never over meta-guidance sections that quote the forbidden patterns by design.
3. For per-unit length ACs (tweet ≤280), bound the range to the single channel the rule
   governs (`sed -n '107,126p'` = X/Twitter only), excluding sibling channels whose units
   have different limits (email/DM paragraphs).

## Key Insight

A grep/wc AC encodes "pattern P must (not) appear in region R." The default mistake is to
run it over the whole file when R is a *subsection*. Two classes of legitimate content
break the document-wide form: (a) **meta-guidance** that names the forbidden pattern as
instruction, and (b) **sibling sections** governed by a different threshold. Always derive
the line range of R from the section map before running the check, and state the scoped
command in the AC verification log so the reviewer can reproduce it.

## Session Errors

1. **Task subagent spawning unavailable inside the planning subagent** (forwarded from
   session-state.md) — plan/deepen-plan fan-out could not run; research done inline.
   Recovery: inline reads of brand-guide.md / marketing-strategy.md / roadmap.md +
   mechanical deepen-plan gates. **Prevention:** known structural constraint — subagents
   cannot spawn sub-subagents (see [[2026-05-12-task-subagent-prompt-text-only]]). The
   parent one-shot session retains Agent-tool access, so plan-review can be re-run at the
   parent level if degraded plan depth matters; for a verbatim-prose docs deliverable the
   degradation is low-risk.
2. **`ZSH_VERSION: unbound variable`** printed during a classification grep — emitted by
   the shell-snapshot wrapper under `set -u`, not by the issued command (output correct).
   **Prevention:** ignore shell-snapshot `unbound variable` lines that name `ZSH_VERSION`
   / shell-init vars; they are environment noise, not command failures.
3. **Review agent (code-quality-analyst) false-positive** — claimed `depends_on` omitted
   `brand-guide.md` when it was the first entry. **Prevention:** verify any "X is
   missing/omitted" agent finding against the actual file (Read/grep) before acting — a
   single-agent claim is a hypothesis, not a verdict.

## Tags
category: best-practices
module: content-authoring
