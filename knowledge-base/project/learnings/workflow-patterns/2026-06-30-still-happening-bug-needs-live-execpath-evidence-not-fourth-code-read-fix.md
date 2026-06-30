---
title: "A 'still happening' bug whose fix already merged needs live exec-path evidence, not a fourth code-read fix"
date: 2026-06-30
category: workflow-patterns
tags: [one-shot, investigation, observability, sentry, supabase, collision-gate, concierge]
issues: ["#5733", "#5734", "#5591"]
---

# 'Still happening' after a merged fix → pull live exec-path evidence before writing another fix

## Problem

`/soleur:go #5733` ("investigate: workspace 754ee124 still strands /soleur:go after
N server-side fixes"). The operator reported the strand was STILL happening. The
issue body proposed an agent-container-vs-server filesystem-divergence hypothesis and
explicitly said: *do NOT ship another server-side fix until the agent's actual
exec-path filesystem is confirmed.*

Two traps were live:
1. **The fix was already merged but not working.** A fourth fix (PR #5734, commit
   `190ab58a5`) had already merged + deployed ~the same day — it shipped the gitdir
   strand heal, the agent self-stop observability, N-co-owner tolerance, AND the
   ADR-044 amendment. So "write the fix" would have duplicated merged code.
2. **The operator confirmed the strand persists POST-deploy.** So the merged fix did
   not heal the surface — exactly the issue's own hypothesis.

## Solution / What worked

**Pull live exec-path evidence directly (no SSH, no dashboard-eyeball) BEFORE
designing any fix.** Three reads decided everything:

- **Sentry (read-only, via `doppler run -p soleur -c prd`):** the expected
  `agent_readiness_self_stop` op was **absent** over 14d despite a confirmed strand —
  even though the agent surface clearly reaches Sentry (`Unknown Bash verb` fired
  post-deploy). Conclusion: the merged observability is **blind** on the real strand
  (a host-side `git rev-parse` runs OUTSIDE the agent's bwrap `denyRead:["/workspaces"]`
  mount). The absence of an expected event is itself decisive evidence.
- **Supabase (read-only, PostgREST + service-role key from Doppler prd):**
  `workspace_members` showed **2 `role=owner` rows** (refuting the "owner-less"
  premise — it was a `.maybeSingle()` ≥2-row false positive), and
  `user_session_state.current_workspace_id == 754ee124` for **all** members. That
  single read **ruled out H3** (wrong active workspace) and **confirmed H2** (agent
  reaches the right dir; its `.git` is invalid to the bwrap `rev-parse`).
- The exact on-disk `.git` shape is the ONE thing not remotely observable — *because
  the observability is blind* — so the fix was made robust to all H2 realizations
  rather than guessing one.

Only THEN was a new one-shot launched, scoped to the genuine gap (rev-parse confirm
gated behind lstat across all 3 gates + a C2 in-sandbox observability backstop +
promote the self-stop fields to searchable Sentry tags).

## Key insights

1. **"Still happening" + an already-merged fix has three branches, distinguished
   only by live data:** (a) fix didn't deploy, (b) fix deployed but heals the wrong
   surface, (c) fix deployed but its observability is blind. Code-reading cannot tell
   them apart. Pull prod Supabase + Sentry yourself (`hr-no-dashboard-eyeball-pull-data-yourself`).
2. **An ABSENT expected telemetry event is evidence, not a dead end.** Confirming the
   `agent_readiness_self_stop` op did not exist (while the surface otherwise reaches
   Sentry) proved the observability was blind — which became the load-bearing fix.
3. **The one-shot collision gate (`gh pr list --search "linked:issue #N"`) does NOT
   catch a fix that referenced the issue in prose but closed a SIBLING issue.** #5733's
   scope shipped in #5734, which closed #5591 and only name-dropped #5733 in its ADR
   amendment — so the gate returned empty and a worktree + empty draft PR were built
   before the planning Phase-0.6 premise-validation (`hr-before-asserting-github-issue-status`)
   caught the already-merged state. The premise-validation is the real backstop; the
   collision gate is necessary-not-sufficient.
4. **Sentry observability emitted as `extra` is NOT searchable.** A "make it
   observable" PR must promote the distinguishing fields (`source`, `gitKind`) to
   TAGS via the `reportSilentFallback` tag-promotion path, or the advertised detection
   query silently returns zero (caught here by observability-coverage-reviewer as the
   only P2).

## Session Errors

1. **one-shot collision gate missed the already-merged fix** — #5733's fix shipped in
   #5734 (closed #5591, only referenced #5733). `linked:issue #5733` returned empty;
   worktree + empty draft PR #5788 were created then torn down. **Recovery:** the
   planning premise-validation caught it; closed #5788, removed the worktree/branch,
   posted the live-evidence diagnosis to #5733. **Prevention:** for a P1 `investigate:`
   issue, before creating the worktree, grep recent merged-PR bodies/diffs for the bare
   issue number (not just `linked:issue`), since a fix can reference-without-linking the
   target. (Already partially backstopped by Phase-0.6 premise-validation.)
2. **`scripts/sentry-issue.sh search` → HTTP 404** — the script fetches by issue-id
   only; it has no `search` subcommand (the plan's `search` verb was aspirational).
   **Recovery/Prevention:** for op/text search, hit the org issues list endpoint
   directly: `curl -sG "https://$HOST/api/0/organizations/$ORG/issues/" --data-urlencode
   "query=<q>" --data-urlencode "statsPeriod=14d" -H "Authorization: Bearer $TOKEN"`
   (HOST=jikigai-eu.sentry.io, token=SENTRY_ISSUE_RO_TOKEN). Validate the harness
   against a known-present issue first (empty results can mean broken query, not absent data).
3. **bash `UID` is readonly** — a `for UID in …` loop errored `readonly variable`.
   One-off. **Prevention:** use `ID`/`uid` (lowercase) for UUID loop vars.
4. **`gh run list --json databaseName` invalid field** — one-off; the field is
   `databaseId`. **Prevention:** `gh <cmd> --json` with an unknown field prints the
   valid set; copy from there.
