---
title: "gh issue create filing gate: --body-file must be absolute AND User-Impact must contain a taxonomy surface word"
date: 2026-11-19
category: workflow-patterns
tags: [filing-gate, gh-issue-create, guardrails, taxonomy, devin]
related: [wg-defer-only-after-inline-triage]
---

# Learning: the filing gate needs an absolute --body-file and a taxonomy-worded User-Impact

## Problem

During the `rundevoo.run` brainstorm (issue #12971), `gh issue create
--body-file <path>` was refused twice by
`guardrails.sh:require-filing-justification`:

1. `--body-file` with a repo-relative path — the hook resolves it against its
   own working directory, not the caller's CWD. Fix: pass a **literal absolute
   path** (no `$VAR`, no `~`).
2. A `User-Impact:` line that named "the rundevoo.run public DNS surface" —
   the gate's EXIT 2 requires the User-Impact value to match
   `.claude/hooks/lib/user-surface-taxonomy.txt` (route, endpoint, page,
   screen, component, button, form, dashboard, CLI, command, email,
   notification, document, report, invoice, digest). "DNS surface" is not in
   the taxonomy; "email sent as @rundevoo.run" is (`email`).

## Key Insight

The gate's denial message lists the three exits but not the *taxonomy file* —
`User-Impact:` must literally contain one of its ~16 words on a word boundary
(case-insensitive). When the consequence is real but abstract ("the public DNS
surface"), name the *concrete* user-visible surface it protects: the email sent
as the domain, the page served on it, the document/ledger recording it.

`Fix-Size:` must match `N lines / M files` exactly once (counted, not parsed
loosely) and exceed the inline threshold (≤100 lines AND ≤4 files → fix inline,
don't file).

**Prevention:** before `gh issue create`, write the body file first (absolute
path), include `User-Impact:` naming a taxonomy surface and `Fix-Size: N lines
/ M files` (or `Mandated-By: <rule-id>` on its own line / `--label
meta/machinery`). Check the taxonomy file when a refusal persists despite
plausible wording.

## Session Errors

1. `gh issue create` ×2 refused (relative --body-file; non-taxonomy
   User-Impact). **Prevention:** as above.
2. `gh milestone list` exited 1 — `gh api repos/{owner}/{repo}/milestones`
   works. **Prevention:** use the API form for milestone enumeration.
3. RDAP one-liner printed "REGISTERED" on `rdapConformance` presence while the
   body was `errorCode: 404` (domain actually available). **Prevention:** check
   `errorCode`/`title` before any presence-based positive claim.
