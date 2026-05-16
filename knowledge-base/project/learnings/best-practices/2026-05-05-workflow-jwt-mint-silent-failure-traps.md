---
date: 2026-05-05
category: best-practices
problem_type: silent_failure_class
component: github_actions_workflow + jwt + gh_api
related_issues: [3187, 3181]
related_prs: [3224]
tags: [github-actions, jwt, openssl, gh-cli, base64url, silent-failure, plan-review-catch]
synced_to: []
---

# Workflow JWT-Mint Silent-Failure Traps — Three Patterns That Pass `--help` But Break In Prod

## Problem

When PR #3187's plan was being drafted (an hourly GitHub App drift-guard
that mints an RS256 JWT, calls `gh api /app`, and asserts identity), three
distinct silent-failure traps surfaced at plan-review time. Each would
have produced a workflow that:

- passes `actionlint` and `yamllint`,
- passes the contract test as initially scoped,
- silently 401s or fires dead-code branches in prod.

All three are well-documented in scattered sources but easy to miss when
authoring a workflow under time pressure. They were caught by the
`kieran-rails-reviewer` agent reviewing the plan against the gh CLI
source and the GHA evaluator semantics — not by static checks, not by
the reviewer's intuition, but by reading the actual contract surfaces.

This learning consolidates the three traps so future workflow authors
catch them at plan-write time, not at their first prod 401.

## Trap 1 — `gh api` does NOT accept JWT-format `GH_TOKEN`

### Symptom

You set `env: { GH_TOKEN: $JWT } gh api /app` expecting `gh api` to send
`Authorization: Bearer <jwt>`. GitHub returns **401 Bad credentials**.

### Root cause

`gh api` sends `Authorization: token <value>` (the `token` scheme, not
`Bearer`). GitHub's App-JWT endpoints (`/app`, `/app/installations`,
`/app/installations/<id>/access_tokens`) require the `Bearer` scheme.
There is no override for the auth header construction; `gh api` picks
the scheme based on the token's static format detection (PAT shape,
fine-grained PAT shape, GitHub App installation token shape) and JWT
does not match any of them.

### Workaround

Use `curl` directly. Pass the JWT via a header file to keep it out of
argv (the runner is ephemeral, but argv-leak is still bad hygiene):

```bash
HTTP_CODE=$(curl -s -w '\n%{http_code}' \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --header @<(printf 'Authorization: Bearer %s' "$JWT") \
  https://api.github.com/app -o "$RESPONSE_FILE")
```

Note: the `<(...)` process substitution writes to `/dev/fd/N` — the JWT
hits the kernel's pipe buffer, not the filesystem, and is gone after the
curl call returns.

### How to verify

If you're unsure whether `gh api` accepts JWT for a specific endpoint,
read the gh CLI source: `cli/cli` repo, `pkg/cmd/api/api.go`, look for
the auth-header construction. Or run:

```bash
GH_TOKEN="$JWT" gh api /app -i 2>&1 | head -20
```

A `401 Bad credentials` with the JWT first ~20 chars echoed back tells
you `gh api` is sending the wrong scheme.

## Trap 2 — `openssl base64 -A` trails a newline that `tr -d '='` does NOT strip

### Symptom

You implement base64url encoding for a JWT segment as
`openssl base64 -A | tr '+/' '-_' | tr -d '='`. The resulting JWT mints,
the workflow calls the API, and GitHub returns **401**. Inspecting the
JWT, it has 3 segments — but one or more contains a literal `\n`.

### Root cause

`openssl base64 -A` (the "single-line" output mode) suppresses the
**embedded** line wrapping of standard base64 output, but it still emits
a **trailing newline** on most LibreSSL builds and older OpenSSL
versions. The `tr -d '='` strip removes only `=` padding; it does not
remove the `\n`. The resulting segment ends in a literal newline, which
then gets concatenated with `.` and the next segment, yielding
`<base64>\n.<base64>` — invalid JWT.

### Workaround

Use `coreutils base64 -w 0` (the "no wrapping" flag, also single-line)
AND extend the strip to cover both `=` padding and `\n`:

```bash
b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\n'; }
```

`base64 -w 0` is on `ubuntu-latest` runners (coreutils is part of the
base image). It does not emit a trailing newline.

### How to verify

In a test harness, mint a JWT through the workflow's mint logic, split
on `.`, and assert no segment contains `\n`:

```javascript
const parts = jwt.split('.');
assert.strictEqual(parts.length, 3);
parts.forEach((p, i) => {
  assert.ok(!p.includes('\n'), `JWT segment ${i} contains newline`);
});
```

This is one of the assertions the contract test for #3187 locks in
explicitly.

## Trap 3 — `if: failure()` does NOT fire when the previous step has `continue-on-error: true`

### Symptom

You wrap a non-critical step (e.g., email notification) in
`continue-on-error: true` so its failure doesn't fail the whole job.
You then add a follow-up step with `if: failure()` to handle the
notification's failure path. **The follow-up never runs.**

### Root cause

GitHub Actions' job-level state machine treats `continue-on-error: true`
as "this step's failure does not propagate to the job's outcome". The
`failure()` conditional checks the **job's** outcome, not the
**previous step's** outcome. Because the email step's failure was
masked from the job, `failure()` evaluates `false` and the cascade
step is dead code.

This is documented but counter-intuitive — most authors expect
`failure()` to inspect the immediately preceding step.

### Workaround

Give the `continue-on-error` step an `id:`, then condition the cascade
on `steps.<id>.outcome == 'failure'` directly:

```yaml
- name: Notify ops on failure
  id: notify
  continue-on-error: true
  uses: ./.github/actions/notify-ops-email
  with:
    subject: "..."
    body: "..."
    resend-api-key: ${{ secrets.RESEND_API_KEY }}

- name: Email-fail cascade
  if: always() && steps.notify.outcome == 'failure' && steps.check.outputs.failure_mode != ''
  run: |
    # Cascade logic here
```

The `always()` ensures the conditional is even evaluated regardless of
job state.

### How to verify

In a test workflow, set the `continue-on-error` step to deliberately
exit non-zero, observe the cascade step's `if:` evaluation in the run
log, and confirm it fires only when the explicit-`outcome` form is
used.

## Why these surface together

All three traps are in the **JWT-mint + gh-api-call + conditional-recovery**
flow that any workflow auditing GitHub App identity will write. Trap 1
is at the API call boundary, Trap 2 is at the JWT signing boundary,
Trap 3 is at the recovery-step boundary. A workflow that addresses one
without the others can still fail silently on the others. They are a
**triplet**, not three independent issues.

## Generalization

These traps share a structure: a CLI/runtime accepts a quasi-correct
input (JWT-shaped string, base64-shaped string, "failed" state), passes
its own surface check, and silently produces wrong output. The remedy
in each case is to **read the actual contract surface** (CLI source,
output of an empirical test, GHA documentation on `failure()`) rather
than rely on the surface check.

The pattern: **for any silent-failure trap, the load-bearing
verification is reading the upstream contract, not running the local
tool's `--help`.**

## Where to apply this

- Authoring any new `.github/workflows/*.yml` that:
  - mints a JWT (RS256, EdDSA, etc.)
  - calls `gh api` with non-PAT auth
  - uses `continue-on-error: true` + a recovery step
- Reviewing PR plans that prescribe these primitives — surface as a
  Sharp Edge in plan-review.
- Refactoring an existing workflow that uses `gh api` with a custom
  bearer token — verify the auth-scheme assumption.

## Cross-references

- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` (related: any
  silent-failure class must produce an alerted signal)
- Learning `2026-04-18-drift-guard-self-silent-failures.md` (related:
  drift-guard tests must survive their own silent-failure modes)
- Learning `2026-04-29-jwt-fixture-reminting-decode-verify.md` (related:
  JWT correctness via decode-and-verify, not snapshot)
- Learning `2026-05-04-github-secrets-cannot-start-with-github-prefix.md`
  (related: another silent CLI-acceptance trap, secrets-API-side)

## Session Errors

Session error inventory: none detected.

The three traps in this learning were captured as **plan-review prevention**, not from a session error. The Kieran review agent flagged all three (P1-1, P1-2, P0-3 in the plan-review output) before any implementation code was written. This learning exists to compound that catch into institutional memory so the next workflow author doesn't need to wait for a parallel review to find the same patterns.
