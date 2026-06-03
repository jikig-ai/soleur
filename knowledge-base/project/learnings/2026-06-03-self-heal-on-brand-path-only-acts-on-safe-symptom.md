---
title: "A self-heal/repair on a brand-critical path must only act on the safe symptom, never destroy existing state"
date: 2026-06-03
category: best-practices
module: apps/web-platform/server/ensure-workspace-repo
tags: [self-heal, brand-survival, git, idempotency, multi-agent-review, sandbox-capability-spike]
---

# Learning: scope a self-heal to the symptom that has nothing to lose

## Problem

PR #4890 added a session-start "ensure-repo" self-heal: if a Concierge
workspace has a connected repo but no clone on disk, clone it. The first design
also tried to *repair* an origin **mismatch** (`.git` present but origin ≠
connected repo) by `rm .git` + re-clone + `checkout -f`.

Multi-agent review (security-sentinel + user-impact-reviewer + the commit
security hook) surfaced three P1s and a HIGH, all rooted in that repair branch:
1. **Data loss** — `rm .git` + `checkout -f` destroys un-pushed commits and
   uncommitted edits.
2. **Start-Fresh destruction** — a "Start Fresh" workspace has a `.git` with NO
   origin, so `normalizeRepoUrl("") !== repoUrl` → mismatch → it got wiped
   (and the plan's own Non-Goal "don't change Start-Fresh behavior" was
   violated).
3. **Solo-vs-active mis-graft** — `workspacePath` was the solo dir while
   `repoUrl`/`installationId` were the active workspace's; the repair grafted
   the active repo into the solo dir.
Plus a HIGH **argv flag-smuggling** (`git clone … <repoUrl>` with no `--`).

## Solution

Restrict the self-heal to the ONE state that has nothing to lose: **`.git`
ABSENT** (the literal prod symptom "No Git repository found"). When any `.git`
exists → **no-op, never touch it**. Repo *reconnect* (origin change) stays the
canonical `/api/repo/setup` wipe-and-reclone path's job, not a background
self-heal's.

Plus: make the graft **retry-safe** by landing `.git` LAST (clone to a temp
subdir → materialize the tracked tree over scaffold → `rename` `.git` in last,
the all-or-nothing success sentinel) so a partial failure leaves the workspace
`.git`-less and the next cold dispatch retries — never a half-grafted state the
no-op guard would permanently mask. Harden the clone argv with `--` + a strict
`github.com` HTTPS allowlist.

## Key Insight

For an automatic repair/self-heal, the safe scope is the symptom where the
"before" state holds no irrecoverable value. "No `.git` at all" has no git
history to lose → grafting is safe. "Wrong/old `.git`" holds potential
un-pushed work → auto-repair is a data-loss vector and must NOT be silent. When
the action is destructive and the threshold is `single-user incident`, prefer
**do-nothing-when-uncertain** over clever repair. Also: make the success
sentinel the LAST mutation so failures self-retry instead of masking.

A second-order insight from the planning spike: a **sandbox-capability question
that source-reading leaves ambiguous can be settled by an empirical PROD
signal**. Source said the agent sandbox (`allowManagedDomainsOnly: true`,
`allowedDomains: []`) might block github.com; the prod symptom — the agent's
in-sandbox `gh auth status` returning "token invalid" (a 401-from-`/user`
verdict, not a connection error) — proved api.github.com WAS reachable
(Outcome A). The live behavior is the authoritative probe.

## Session Errors

1. **Backtick in `git commit -m` body triggered shell command substitution** —
   a `` `git clone … -- <repoUrl>` `` phrase inside the double-quoted `-m`
   string was eaten by `$(...)`-style substitution, dropping the phrase from the
   commit body (cosmetic; meaning survived). **Prevention:** never put
   backticks or `$(...)` in a `git commit -m "..."` string — use `--body-file`,
   a heredoc, or drop the backticks. (Same class as the trailer-contiguity and
   heredoc-in-hooked-command gotchas already documented.)
2. **Initial self-heal design shipped a destructive repair branch** — caught by
   multi-agent review, not by the unit tests (the tests asserted the repair was
   *called*, not that destruction was *safe*). **Prevention:** for any
   destructive auto-action, a review lens must ask "what irrecoverable state
   does the 'before' hold?" — encoded now as this learning + the conservative
   no-`.git`-only scope.
