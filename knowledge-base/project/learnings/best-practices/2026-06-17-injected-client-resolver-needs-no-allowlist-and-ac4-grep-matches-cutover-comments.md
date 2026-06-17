---
title: "Injected-service-client resolvers need no allowlist entry; an AC4 grep for the OLD column matches your own cutover comments"
date: 2026-06-17
category: best-practices
module: apps/web-platform/server
tags: [service-role-allowlist, resolver-pattern, adr-044, grep-acceptance-criteria, review-false-positives]
issue: 5470
pr: 5481
---

# Learning: injected-client resolvers need no allowlist entry; AC4 "grep for the removed column" matches your own cutover comments

## Problem

PR #5470 added a service-role-safe installation resolver and cut two Inngest
readers off `users.github_installation_id`. Two recurring traps surfaced:

1. The plan's Decision 4 prescribed adding the new resolver to
   `.service-role-allowlist`. But the chosen design (mirror
   `workspace-identity-resolver.ts`: an **injected** `service: ServiceClient`
   param) means the resolver imports NO `createServiceClient`/`getServiceClient`
   factory — so the CI `service-role-allowlist-gate` (which flags *importers*)
   never sees it, and adding an entry would falsely imply the file imports
   service-role. The precedent `workspace-identity-resolver.ts` is itself NOT
   allowlisted, confirming the correct shape.
2. The acceptance criterion `git grep 'users.*github_installation_id'
   server/inngest/ == 0` matched my OWN new explanatory comments — the cutover
   comments that *describe* the removed read (e.g. "the legacy
   `users.github_installation_id` predicate is dropped") contain the exact
   pattern the grep hunts. The code was correct; the comments tripped the gate.

## Solution

1. **Injected-client resolvers get NO allowlist entry.** The allowlist gates
   *importers* of the service-role factory. A resolver that receives the client
   by injection (testable, mirrors `workspace-identity-resolver.ts` /
   `org-memberships-resolver.ts`) imports only `reportSilentFallback` and is
   correctly absent from the allowlist. The service-role privilege stays
   anchored at the *callers* (already allowlisted), which is good
   dependency-inversion. When a plan says "add the new file to the allowlist",
   verify whether the file actually imports the factory before doing so.
2. **When an AC greps for the column you removed, reword the cutover comments
   so the two tokens don't co-occur on one line.** Describe the change as "the
   legacy `users` install predicate" rather than spelling
   `users.github_installation_id`. Verify with the literal AC grep, not by
   eyeballing the code diff — comments are in scope.

## Key Insight

A grep-based "the old pattern is gone" AC has two blind spots that mirror each
other: it matches the comments that *explain* the removal (false fail on correct
code), and — being single-line — it can MISS a multi-line `from("users")…
select("…github_installation_id")` read (false pass). Treat such an AC as
necessary-but-not-sufficient: also confirm the reads are structurally gone, and
that every remaining `github_installation_id` hit is a legitimate `workspaces`
read.

## Session Errors

1. **Closed contextual `#5462` citation in one-shot args** — Recovery: re-invoked
   one-shot with `#5462`/`#5437` scrubbed to date-anchored prose, keeping only the
   OPEN work-target `#5470` in `#N` form. **Prevention:** already covered by the
   `/soleur:go` Sharp Edge "Scrub closed `#N` contextual citations before invoking
   one-shot" and learning `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs`.
   The router should scrub at routing time; recovery at the one-shot layer also works.
2. **`set -uo pipefail` tripped the shell snapshot** (`ZSH_VERSION: unbound variable`)
   — Recovery: re-ran without `set -u`. **Prevention:** one-off; the harness shell
   snapshot references unbound vars incompatible with `set -u` — prefer `set -o pipefail`
   alone in ad-hoc predicates.
3. **`git show HEAD:server/...` path error** — Recovery: used `HEAD:./server/...`
   (cwd-relative). **Prevention:** one-off; `git show HEAD:<path>` is repo-root-relative
   unless `./`-prefixed.
4. **`vi.mock` hoisting (`Cannot access spy before initialization`)** — Recovery:
   `vi.hoisted()`. **Prevention:** documented vitest gotcha (work skill Sharp Edges);
   caught by the RED run, which is the gate working as intended.
5. **AC4 grep matched own cutover comments** — Recovery: reworded comments.
   **Prevention:** this learning (reword so `users`/`github_installation_id` don't share a line).
6. **git-history-analyzer review false positives (stale bare-repo read)** — Recovery:
   cross-reconcile + `git show HEAD:` verification. **Prevention:** already covered by the
   review skill's bare-repo / cross-reconcile guidance.

## Tags
category: best-practices
module: apps/web-platform/server
