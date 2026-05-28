---
module: github-app
date: 2026-05-28
problem_type: logic_error
component: planning
symptoms:
  - "Plan asserted a GitHub App permission scope was 'provably unused (grep returned zero hits)'"
  - "The scope was actually load-bearing; dropping it would 502 every org-installed user"
root_cause: grep_missed_interpolated_path_form
severity: high
tags: [planning, grep-provability, multi-agent-review, github-app, near-miss]
synced_to: [plan]
---

# Learning: "grep proves X is unused" must cover interpolated / template-literal API-path forms

## Problem

In the #4189 cron-observability fix, the plan's Hypothesis-Verification table
asserted `members: read` on the GitHub App was **unused** — "`rg` for
`/orgs/.../members`, `/memberships`, `/teams` → ZERO hits" — and proposed
DROPPING the scope to clear an `installation_permission_drift`. That conclusion
was **false**. `apps/web-platform/server/github-app.ts` calls the membership API
in two live, tested paths:

- `verifyInstallationOwnership()` (`:305-308`) — gates org-level repo connect
- `findOrgInstallationForUser()` (`:419-420`) — gates installation auto-detect

Both interpolate the path:

```ts
`${GITHUB_API}/orgs/${account.login}/members/${expectedLogin}`
```

A grep for the literal substring `/orgs/.../members` (or `/orgs/{org}/members`)
does NOT match `/orgs/${account.login}/members/${expectedLogin}` — the
interpolation splits the path across template-literal expression boundaries.
Dropping `members:read` would have made every org member's repo-connect /
auto-detect return 502 / `not_installed` (GitHub returns 403 on the membership
call without the scope; the code maps non-{204,404,302} to a 502 fall-through).

## Solution

Caught at multi-agent PR review — `security-sentinel` AND `user-impact-reviewer`
independently surfaced it (two orthogonal agents concurring is the high-signal
pattern). Fix: revert the drop, RETAIN `members:read`. The drift clears the
correct way — the same operator re-consent that grants the newly-raised
`issues:write` ALSO grants the long-declared-but-ungranted `members:read` (both
are manifest-above-live, so one click covers both).

## Key Insight

A planning claim of the form "field/scope/symbol X is provably unused because
`grep <literal> returned zero`" is only as strong as the grep's coverage of how
X is actually referenced. For anything reachable via a **string-interpolated**
construction — REST paths built with template literals (`/orgs/${org}/members/`),
dynamic property access (`obj[key]`), computed config keys, SQL built by
concatenation — a literal-substring grep produces a FALSE zero. Before asserting
"unused → safe to remove":

1. Grep the **stable anchor** of the path, not the whole path. For
   `/orgs/${org}/members/${user}` the anchor is `/members/` or `members/${`,
   not `/orgs/.../members`.
2. Grep the **API verb family** (`/members`, `/memberships`, `/teams`) AND the
   interpolation-boundary form (`}/members`, `members/${`).
3. Prefer a semantic search (find the function that builds the URL) over a
   path-literal grep when the path is dynamic.

Removal is destructive; the cost of one extra grep is trivial against the cost
of a single-user-incident regression.

## Session Errors

- **Plan's "members:read unused" hypothesis was false (P1 near-miss).** The
  grep missed the template-literal form `/orgs/${...}/members/${...}`. Recovery:
  multi-agent review caught it; reverted the drop, retained the scope.
  **Prevention:** grep the stable path anchor + interpolation-boundary forms,
  not the literal full path, when proving an interpolated API path is unused.
- **Plan over-counted affected crons ("FOUR", actually THREE).**
  `cron-community-monitor` mints a token and spawns `gh` in a subprocess — it
  has no in-process octokit catch, so the `issue_write_403` discriminator is
  structurally inapplicable. Recovery: added the discriminator to the real
  third cron (`cron-stale-deferred-scope-outs`), corrected the count.
  **Prevention:** when enumerating "all callers that share pattern P," verify
  each candidate actually exhibits P's structural shape (in-process catch vs.
  subprocess), not just that it touches the same helper.
- **Primary fix (`issues:write`) was test-unguarded.** The parity test asserted
  the permission KEY-SET only, not the `issues` VALUE, so a silent
  `issues→read` revert would pass green. Recovery: added a dedicated
  `default_permissions.issues === "write"` value assertion.
  **Prevention:** when a fix flips a value the existing test only checks
  structurally (key presence, count), add a value-level assertion for the
  specific value the fix depends on.
- **(forwarded) `soleur:plan` wrote the plan to the bare-repo root** instead of
  the worktree (Bash CWD resets per-call). Recovery: planning subagent moved it.
  **Prevention:** already covered by the one-shot CWD-verification step.
