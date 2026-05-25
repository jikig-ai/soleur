---
title: PR-1 of a sequenced legal-then-code rollout needs Article 13(3) temporal qualifiers
date: 2026-05-25
category: best-practices
tags: [legal-compliance, sub-processor-disclosure, multi-pr-sequencing, art-13-prior-disclosure]
---

# Learning: PR-1 of a sequenced legal-then-code rollout needs Article 13(3) temporal qualifiers

## Problem

PR-1 of umbrella #4456 (`feat-audit-env-flags-flagsmith-policy`) lands Bullet Train Limited (Flagsmith) sub-processor disclosure across 9 legal artifacts BEFORE PR-2's code-side egress of workspace `orgId` identity-trait. This is the correct sequencing under Article 13(1)(e) (controllers must disclose recipients before processing begins). But the initial PR-1 commit wrote the disclosures in **present tense** ("`transient: true` MANDATORY on every call", "data egresses to Flagsmith via `getIdentityFlags(identifier, { role, orgId }, true)`") — describing the post-PR-2 architecture as if it were already live.

The actual code at PR-1 merge time (`apps/web-platform/lib/feature-flags/server.ts:86`) calls `getIdentityFlags(\`role:${role}\`, { role })` — no third-arg `transient`, no `orgId` trait. The disclosed data envelope and the egressed data envelope did not match.

Three independent multi-agent reviewers caught this:

- `legal-compliance-auditor` flagged it as P1 "code-vs-prose contradiction — Art. 13(1)(e) / Art. 14(1)(e) accuracy defect AND Art. 5(1)(a) lawfulness/transparency defect".
- `security-sentinel` named the same pattern as "forward-looking commitment depending on PR-2 enforcement".
- `user-impact-reviewer` Finding 7 noted "§5.15 'Right to erasure' absolute claim depends on PR-2 actually passing `transient: true` at every call site".

The plan-time review of PR-1 (DHH + Code Simplicity + Kieran consensus) did NOT surface this because the plan reviewers framed PR-1 as "doc-only PR — small risk". The drift between disclosure prose and current code state was invisible at plan time; it surfaced only when multi-agent review at PR-time cross-grepped the disclosure prose against the actual `server.ts` call site.

## Solution

For any PR-1 in a sequenced legal-then-code rollout (or any "land disclosure before code" pattern), use the **Article 13(3) prior-disclosure pattern**: write the disclosure in future-tense or qualified-present-tense, naming the PR that lands the code-side enforcement.

Templates:

| Bad (present-tense — implies live behavior) | Good (Art. 13(3) prior-disclosure) |
|---|---|
| "`transient: true` MANDATORY on every call" | "`transient: true` MANDATORY on every call **(effective on PR-2 of umbrella #4456 merge)**" |
| "Pseudonymised `identifier` + `{role, orgId}` egress" | "Will egress pseudonymised `identifier` + `{role, orgId}` **(effective on PR-2 merge)**" |
| "No persistent identity record is created on Flagsmith's side under `transient: true`" | "**Once PR-2 of umbrella #4456 merges,** no persistent identity record will be created..." |
| "Every flag flip is the AND of Flagsmith boolean AND env-allowlist" | "**Will require** the AND of Flagsmith boolean AND env-allowlist **(effective on PR-2 merge)**" |

Additionally:
- Document the **current code-side baseline** explicitly so an external auditor can verify the gap is bounded. PR-1's revised `flagsmith.md` "Current code-side state at PR-1 merge (before PR-2)" subsection names the pre-PR-2 call site, the cardinality of the role-bucket key, and the absence of per-user identity trait egress. This is the auditor-readable proof that PR-1 is prior-disclosure of a known forthcoming change, not misrepresentation.
- Cite the precedent (Soleur uses the 2026-05-12 `messages.usage` disclosure shape in `compliance-posture.md` — same pattern: "added in [date] (PR #X) — production state at merge: enabled").

## Key Insight

**A sequenced legal-then-code rollout has a "disclosure-window" attack surface that plan-time review does not catch.** The legal docs go public on PR-1 merge; the code that honors them goes live on PR-N+1 merge. In the window between PR-1 and PR-N+1, the public-facing disclosure misrepresents the actual processing state. Even if no user is harmed (because the disclosed processing is more conservative than the actual processing — fewer traits, not more), the disclosure is **factually wrong** and creates Art. 13(1)(e) / Art. 5(1)(a) liability.

Multi-agent review at PR-1 time catches this only when the spawn prompt explicitly asks "for each forward-looking claim, identify the PR that lands the code-side enforcement and verify the disclosure prose uses temporal qualifiers". Without that prompt, plan-time review optimizes for "is the disclosure accurate post-PR-N+1?" (yes) and misses "is the disclosure accurate at PR-1 merge?" (no).

The fix is mechanical: any disclosure claim that depends on code that ships in a later PR MUST use a temporal qualifier naming the dependent PR. The Article 13(3) prior-disclosure framing is the legal precedent (the controller is allowed to disclose forthcoming processing before it goes live; misrepresenting forthcoming processing as live processing is not).

This is symmetric to the existing `pdr-when-a-user-message-contains-a-clear` class of cross-artifact contract drift documented in review/SKILL.md, but for the **temporal axis** rather than the **cross-document axis**: same shape ("the claim is true only if the dependent artifact agrees"), different boundary ("the dependent artifact lands on a later date" vs "the dependent artifact lives in a sibling file").

## Session Errors

- **Initial `git branch --show-current` failed at the bare repo root with "fatal: this operation must be run in a work tree"** — Recovery: cd-ed into the worktree at `.worktrees/feat-audit-env-flags-flagsmith-policy/`. **Prevention:** already covered by `hr-when-in-a-worktree-never-read-from-bare`; could add a session-start hook check that asserts cwd is a worktree path before running any git operation, but this fires on most session starts and `pwd` check is cheap.
- **Edit errors on `compliance-posture.md` and `tenant-dpa-register.md`: "File has not been read yet"** — Recovery: ran Read first, then Edit succeeded. **Prevention:** already covered by `hr-always-read-a-file-before-editing-it`. The Bash `grep` / `head` reads I did before editing are NOT Read-tool reads; the Edit gate requires the Read tool specifically. Recurring pattern; worth a session-start reminder.
- **WebFetch 404s on `https://www.flagsmith.com/legal/dpa` and `/legal/sub-processors`** — Recovery: WebSearch with `flagsmith.com` domain filter to discover canonical URLs (turns out Flagsmith has `/terms-of-service`, `/privacy-policy`, `/gdpr-sub-processor-list` at root, not under `/legal/`). **Prevention:** when fetching vendor legal docs, try the vendor's root sitemap or WebSearch domain-restricted first; don't guess path conventions.
- **code-quality-analyst P1 false-positive on mig 068 revert** — agent used `git diff origin/main..HEAD` (two-dot) and reported PR-1 reverting a hotfix that PR doesn't touch. **Prevention:** already covered by review/SKILL.md Sharp Edges ("verify with `git diff origin/main...HEAD --name-only` (three-dot) before accepting"). Recovery: verified with three-dot diff. **Workflow gap:** the agent's own instructions presumably already say to use three-dot — the false positive happened anyway. Could add a PreToolUse hook that intercepts `git diff main..HEAD` patterns and rewrites them, but that's invasive. Suggest documenting this as a recurring agent-side error class.
- **Cited "PR #4051" throughout PR-1 first commit; #4051 is open issue, merged PR was #4081** — caught only at multi-agent review by git-history-analyzer. **Prevention:** before citing any "PR #N" in a legal artifact, run `gh pr view N --json state` and verify `state == "MERGED"`. If `gh issue view N --json state` returns a real issue with the same number, the citation should be `issue #N / PR #M` (the pairing). Same pattern as `wg-before-asserting-github-issue-status`.
- **Prose-vs-code temporal qualifier gap landed in PR-1 commit** — see Problem section above. **Prevention:** see Solution section.

## Workflow Feedback Proposal

**Proposed addition to `plugins/soleur/skills/work/SKILL.md` Phase 2 step 4 ("Follow Existing Patterns"):**

When the PR is part of a multi-PR sequence and ships disclosure/documentation BEFORE the code that honors the disclosure, every present-tense claim about code-side behavior MUST be guarded by a temporal qualifier ("effective on PR-N merge", "will pass", "once PR-N merges"). Cheapest gate: at Phase 2 review, grep the diff for `MANDATORY|MUST pass|always|every call` patterns and verify each is either (a) backed by current code (grep `apps/`) or (b) qualified with the PR that lands the code. Otherwise the disclosure misstates current state and creates Art. 13(1)(e) / Art. 5(1)(a) liability for regulated-data PRs. **Why:** PR #4455 (umbrella #4456 PR-1) — disclosed `transient: true` MANDATORY before PR-2 code landed; caught by 3 multi-agent reviewers but should have been caught at /work time.

**Proposed addition to `plugins/soleur/skills/review/SKILL.md` "Defect Classes This Review Reliably Catches":**

- **Temporal-qualifier gap on sequenced legal-then-code rollouts** — when PR-1 of a multi-PR sequence lands disclosure prose for behavior that PR-N+1 will implement, present-tense disclosure claims ("`transient: true` MANDATORY", "egresses to vendor") misrepresent current state. Multi-agent review reliably catches this when the spawn prompt instructs `legal-compliance-auditor` to "for each forward-looking claim, identify the PR that lands the code-side enforcement and verify the disclosure prose uses temporal qualifiers". Reviewer takeaway: when reviewing a legal-doc-only PR that cites a forthcoming code PR (PR-N+1), grep the disclosure prose for `MANDATORY|MUST|always|every|egresses` and verify each is qualified with the dependent PR number. Same pattern as cross-artifact contract drift but on the temporal axis. PR #4455 — `legal-compliance-auditor` + `security-sentinel` + `user-impact-reviewer` independently surfaced 4+ instances; fixed with Article 13(3) prior-disclosure pattern.
