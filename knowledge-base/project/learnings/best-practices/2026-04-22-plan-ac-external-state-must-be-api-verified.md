---
module: System
date: 2026-04-22
problem_type: best_practice
component: development_workflow
symptoms:
  - "Plan AC claimed 'dev Doppler has all 6 NEXT_PUBLIC_* secrets; confirmed by codebase audit'"
  - "Dev Doppler was actually missing 3 keys (SENTRY_DSN, VAPID_PUBLIC_KEY, GITHUB_APP_SLUG)"
  - "Happy-path smoke at work-phase failed immediately; AC had to be rewritten"
  - "Plan review looked green because no reviewer queried the live API"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [planning, external-services, doppler, verification, acceptance-criteria, plan-ac]
---

# Plan ACs on external-service state must be API-verified, not code-grep-inferred

## Problem

During planning for PR-B of the `feat-app-url-hardening` bundle (#2769 — CI
guard for required `NEXT_PUBLIC_*` secrets in Doppler prd), the plan's
Acceptance Criteria included:

> Happy-path smoke: `doppler run -c dev -- bash scripts/verify-required-secrets.sh` exits 0 with six `ok <KEY>` lines (**dev config has all 6; confirmed by codebase audit**).

The italicized claim was false. The "codebase audit" was a grep for
`process.env.NEXT_PUBLIC_*` across the app that confirmed six keys were
*read* by runtime code. It did NOT confirm the Doppler `dev` config actually
*held values* for those keys. Dev was missing three (`NEXT_PUBLIC_SENTRY_DSN`,
`NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `NEXT_PUBLIC_GITHUB_APP_SLUG`) — unrelated to
this PR, but load-bearing for the AC.

The error surfaced only at work-phase when the first happy-path smoke returned
exit 1. All three plan-review agents (DHH, Kieran, code-simplicity) saw the
AC as written and none flagged it — there is no way for a plan-reviewer to
detect an unverified external-state claim without making the API call
themselves.

## Root Cause

A code-grep answers the question "does code read key X?" — it cannot answer
"does the config hold a value for X?" These are different questions. The
planner conflated them because both were satisfied by `rg` (same tool, same
habit, different semantics).

Generalizes beyond Doppler:

- **Supabase:** plan AC claims "table `users` has 342 rows" based on a
  migration file — but the migration seeded test data, not prod data.
- **Cloudflare:** plan AC claims "WAF rule R1 is applied" based on a
  `cloudflare_ruleset` in `.tf` — but terraform plan never ran, the
  rule was never applied, and the live zone behaves differently.
- **GitHub secrets:** plan AC claims "repo secret `FOO` is set" based on
  finding `${{ secrets.FOO }}` in a workflow — but `secrets.FOO` is
  trivially absent in fork PRs and could be absent on the base repo.
- **Stripe:** plan AC claims "product X has tier Y configured" based on
  reading `verify-stripe-prices.ts` — but that script's manifest can
  drift from the live Stripe dashboard.

The common failure mode: **the planner asserts a property of external state
by reading the local proxy (code, IaC config, migration file, script manifest)
rather than querying the authoritative source (the API).**

## Solution

**When a plan AC claims a property of external-service state, verify with the
actual API at plan time. Code-grep confirms consumers; only the API confirms
values.** The verification cost is always one CLI call; the cost of an
unverified AC is one wasted work-phase iteration plus a plan-review cycle
that looked green but drifted against reality.

Applied to Doppler specifically:

```bash
# For each key in the AC's claimed-present list:
doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c <config> --plain
# Non-empty output → verified. Empty/missing → fix the AC, don't fix the config as a side-quest.
```

Applied to this PR: the AC was rewritten from `-c dev` to `-c prd` (which
actually holds all 6). Read-only invocation; no prod write. The script
behavior is unchanged — only the AC description corrected to match reality.

For future plans touching any external service:

1. At plan-time, enumerate every external-state assertion in the AC.
2. For each, write the single verification command that would confirm it
   against the live API.
3. Run each command and paste the one-line result into the plan body (or a
   "Research Reconciliation" table).
4. If the verification fails, update the AC (or drop the assertion) — do
   NOT silently plan around missing state.

## Prevention

- **Plan skill Sharp Edge (routed to `plan/SKILL.md`):** When a plan AC
  claims the state of an external-service config (Doppler values, Supabase
  rows, Cloudflare applied state, GitHub secret presence), verify via the
  actual API at plan time — code-grep confirms consumers, not config
  contents.
- **Deepen-plan:** when a plan is enhanced by `/deepen-plan`, one of the
  parallel research agents should query named external services mentioned
  in the AC.
- **Reviewers:** plan-review agents cannot enforce this. The check must
  land during plan drafting or not at all.

## Session Errors

**Worktree ghost after `worktree-manager.sh --yes create`** — The
worktree-manager script printed `✓ Worktree created successfully!` and a
path, but subsequent `git worktree list` and `git branch --list
feat-app-url-ci-guard` both returned empty. The directory at the printed
path existed but contained only the plan file I had written into it. Root
cause unclear (possible race with parallel cleanup, filesystem-level issue,
or script exit without git update). **Recovery:** backed up the plan to
`/tmp/plan-backup.md`, `rm -rf` the stub directory, re-ran `--yes create`
(which succeeded properly this time), verified via `git worktree list |
grep feat-app-url-ci-guard` AND `git -C <path> rev-parse --abbrev-ref HEAD`,
restored the plan. **Prevention:** after `worktree-manager.sh --yes create`
reports success, assert `git worktree list | grep -q <branch>` AND `git -C
<new-path> rev-parse --git-dir >/dev/null 2>&1` before declaring the
worktree usable. The script's own success output is necessary but not
sufficient.

**Unverified plan AC on external-service state** — documented above as the
headline learning.

**Narrow exhaustiveness grep in plan draft** — The plan's first-pass
Research Reconciliation table grepped
`apps/web-platform/{app,server,lib}` for `process.env.NEXT_PUBLIC_*` —
missed consumers in `components/`, `hooks/`, `middleware.ts`, and
`sentry.*.config.ts`. Kieran plan-review flagged as S1 HIGH. Broader grep
revealed a 7th key (`NEXT_PUBLIC_AGENT_COUNT`) that had to be explicitly
excluded with a build-time-Docker-ARG rationale. **Recovery:** plan
Research Reconciliation updated before implementation started; AC's
exhaustiveness re-check inherits the broader scope. **Prevention:** when a
plan freezes a list derived from a grep, the grep scope at plan time MUST
cover every runtime-reachable directory for that consumer class (`app/`,
`server/`, `lib/`, `components/`, `hooks/`, middleware, config files) —
not just the directories the feature author happens to edit.

**CWD drift across Bash calls in a parallel pipeline** — After `cd
apps/web-platform && doppler run -c prd -- ...` ran in one Bash call, a
subsequent Bash call `python3 -c "yaml.safe_load(open('.github/workflows/...'))"`
resolved the relative path against the drifted CWD and failed with
`FileNotFoundError`. **Recovery:** used absolute worktree path in the
retry. **Prevention:** existing rule
`cq-for-local-verification-of-apps-doppler` covers this — chain
`cd <abs-path> && <cmd>` in a single Bash call; don't rely on prior shell
state. Not a new rule, an enforcement miss.

## Cross-References

- Related: `knowledge-base/project/learnings/2026-04-21-cloudflare-block-ai-bots-feature-bypasses-waf-phase-pipeline.md`
  (Cloudflare IaC drift caught only at apply-time — same failure mode,
  different service.)
- Related: `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`
  (Plan preflight for CLI forms — same general principle, applied to CLI
  invocations rather than external state.)
- Related: `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`
  (Spec-vs-codebase reconciliation — this learning extends the principle
  to spec-vs-external-state.)
- Issue: [#2769](https://github.com/jikig-ai/soleur/issues/2769)
- PR: `feat-app-url-ci-guard` branch (3 commits; PR-B of
  `feat-app-url-hardening` bundle)
- Plan: `knowledge-base/project/plans/2026-04-22-feat-app-url-ci-guard-plan.md`
