---
title: A proof-by-absence close on a flag-gated surface proves nothing
date: 2026-09-25
category: logic-errors
module: web-platform/c4, follow-through
tags: [follow-through, feature-flags, proof-by-absence, path-traversal, concierge-prompt]
issues: ["#8740", "#8853", "#8861", "#8739"]
---

# Learning: a proof-by-absence close on a flag-gated surface proves nothing

## Problem

#8740: one external tenant repo had a committed `model.likec4.json` with 40 elements and 0 views, so the C4 editor showed "View `index` not found". The plan (#8853) added a read-side diagnostic on `GET /api/kb/c4/project`, a debounced Sentry warn (`op=zero-view-model`), and a ~490-line follow-through probe that would auto-close #8740 after 14 days with zero production zero-view events, a live-deploy ancestry check, and a sink-liveness check.

The review found the probe could never mean what it claimed. A read-only `flag-list` showed `c4-visualizer` is `default_enabled=false`, on only for the `role-dev` segment in dev and prd. The C4 viewer is the only UI caller of the route, so the external tenant almost certainly cannot load the diagram at all: the signal query returns 0 by construction and the probe would close #8740 with the tenant's model still broken. The structural review added that "fix live" was really "prod descends from the commit that added the probe", "sink live" was any production startup, and the drift row pinned route text rather than the live call.

## Solution

- The CTO ruled option A: delete the probe; #8740 stays open (`Ref`, not `Closes`) and closes by hand on a read-only census re-run finding 0 zero-view models. The Sentry warn remains the ongoing signal. Plan, decision challenges, tasks and the ADR-050 addendum were amended with superseded banners rather than rewritten.
- The route copy says "This is not caused by your diagram source" (the source is not validated on this path) and asks the Concierge to "re-render this diagram", the phrase the prompt addendum keys on.
- The Concierge addendum re-renders by appending one `//` line to the SMALLEST `.c4` file in the canonical folder. The original "add a comment line to one `.c4` file" forced a full-file rewrite through a tool that takes the whole file, and the dogfood `model.c4` is 189 KB with lines over 2000 characters, past what the Read tool returns losslessly.
- The same `%2e%2e` / backslash traversal the route fix closed existed in `kb/upload` and `kb/file` (delete, rename). The filing gate put the fix inside the ADR-131 inline threshold, so it was fixed here with a shared `server/kb-github-path.ts` guard. Validation and encoding are separate: `git/trees` JSON bodies need the RAW path, so encoding applies to URLs only.

## Key Insight

Before designing a close that fires on the ABSENCE of a signal, ask who can produce the signal and whether they can reach the surface that emits it. A feature flag, a role gate, or an unshipped UI makes the absence certain regardless of the underlying state. Measure reachability (`flag-list`, the cohort of the affected party) at plan time; if the affected party cannot reach the emitter, the close needs direct evidence (a census) or stays manual.

Two smaller ones: an allowlist validator for user-named paths rejects legitimate names (spaces, non-ASCII) that work today, so start from the repo's blocklist precedent (`server/validate-context-path.ts`); and a prompt that asks an agent to "add a line" through a whole-file-replace tool is asking for a whole-file rewrite, so bound it (smallest file, append-only).

## Session Errors

1. **Planning subagent's `gh issue create` blocked twice** (missing `--milestone`; body file outside the worktree). Recovery: added the milestone, staged the body in the specs dir. **Prevention:** already hook-enforced; write issue bodies inside the worktree and pass `--milestone` from the start.
2. **Plan write blocked by a banned-token guard.** Recovery: rephrased. **Prevention:** hook-enforced; one-off.
3. **A mutation substitution did not land (backslash quoting in a shell-embedded Python string).** Recovery: the NOLAND assertion caught it; retried with a quoted heredoc. **Prevention:** always assert a mutation landed (`s.count(a)==1`) before scoring it; use `<<'PY'` heredocs for any string containing backslashes.
4. **`test-all.sh --affected` degraded to full (`runner-changed`) and was REFUSED rc=4 on a sibling full run; the `TEST_GROUP=affected` substitute queued 29 min at position 2 and was cancelled.** Recovery: ran the targeted suites and every repo-wide ratchet directly; CI's full battery is the merge gate. **Prevention:** a diff that adds a `run_suite` row forces the full-battery fallback; expect it on any PR registering a suite, and budget for queueing.
5. **`--print-affected-set` preview exceeded the 180 s timeout.** Recovery: skipped the preview and launched the gate. **Prevention:** one-off under machine contention.
6. **The plan's ASCII allowlist for `dir` would have 400'd folders with spaces or non-ASCII names.** Recovery: per-segment blocklist + encoding, matching `validate-context-path.ts`. **Prevention:** grep the repo for an existing validator of the same input class before prescribing one.
7. **A control-character regex would have grown the eslint `no-control-regex` ratchet.** Recovery: a charCode loop. **Prevention:** the eslint warning is the gate; use a loop for control-character checks.
8. **The plan's follow-through probe was vacuous: the affected tenant cannot reach the flag-gated viewer.** Recovery: CTO option A deleted it (~490 lines). **Prevention:** plan sharp-edge bullet added: check the flag cohort before a proof-by-absence close.
9. **The Concierge addendum forced a full-file rewrite of possibly huge `.c4` files (review P1).** Recovery: smallest-file, append-only wording plus a test pinning it. **Prevention:** captured above; review's agent-native seat catches it.
10. **The filing gate refused the traversal issue three times with its generic message, not the inline-threshold one.** Recovery: fixed inline per ADR-131. **Prevention:** cause not verified (the body carried `User-Impact:` and `Fix-Size:` lines); if it recurs, read `guardrails.sh`'s body parse before re-trying.
11. **Two notes edits failed their anchor assertions on backslash escaping.** Recovery: located the anchor by index. **Prevention:** anchor multi-line edits on text without backslashes.
12. **markdownlint MD032 after inserting banners beside lists.** Recovery: blank lines. **Prevention:** one-off.
13. **`kill_mine` refused a same-process-group match.** Recovery: none needed. **Prevention:** one-off.
