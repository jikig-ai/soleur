---
module: Web Platform Infrastructure
date: 2026-05-20
problem_type: workflow_drift
component: tooling
symptoms:
  - "`terraform plan` fails with `Error: No value for required variable` on `apply-web-platform-infra.yml` post-merge"
  - "PR adds 4 new `variable \"...\" { sensitive = true }` blocks; issue body asks operator to mint each in vendor dashboards"
root_cause: design_smell
resolution_type: rule_addition
severity: medium
tags: [terraform, doppler, github-app, iac, autonomy, operator-mint]
synced_to: []
---

# `variable { sensitive = true }` is the most expensive secret-supply shape — exhaust autonomous paths first

## Problem

PR-H #4066 (Daily Priorities multi-source webhook ingress) added four new sensitive variables to `apps/web-platform/infra/variables.tf`:

- `github_app_client_id`
- `github_app_client_secret`
- `github_actions_token` (fine-grained PAT)
- `doppler_token_kb_drift` (Doppler service token)

The PR shipped without populating Doppler `prd_terraform`. Three weeks later, when `apply-web-platform-infra.yml` (#4122) tried to run the canonical `terraform plan` post-merge, it failed with `Error: No value for required variable` on all four. Issue #4150 proposed the path of least resistance: "Operator actions required — mint each credential in a vendor dashboard and paste into Doppler `prd_terraform`." That's 4 manual steps across 3 vendor surfaces (GitHub Apps UI, fine-grained PAT page, Doppler dashboard) per fresh-clone operator, per credential rotation, in perpetuity.

## Root cause — design smell at variable-declaration time

A `variable { sensitive = true }` block is the **least flexible** secret-supply path:

- Every consumer (dev workstation, CI runner, drift detector) needs its own copy of the credential in its Doppler/secret-store.
- Rotation requires touching N consumer surfaces, not 1 producer surface.
- The runbook cost grows linearly with consumer count; the variable block looks like 5 lines of HCL at PR time but loads cost onto every downstream surface forever.

The IaC providers Soleur already loads have higher-affinity primitives that the PR-H author skipped:

- `doppler_service_token` (DopplerHQ/doppler ≥1.x): mints config-scoped Doppler tokens in-band using the provider's workplace-scope auth.
- `random_id` / `random_password` (hashicorp/random): for Soleur-generated secrets where the value is opaque (webhook secrets, signing keys).
- `app_auth { id, installation_id, pem_file }` (integrations/github ≥6.x): exchanges App credentials for a short-lived installation token at each plan/apply, replacing long-lived PATs.

Skipping these in favor of `var.X` is a design smell because the variable-shaped solution looks cheap at PR time but is the most expensive choice over the lifecycle.

## Resolution — 4 operator-mints collapsed to 0 net-new credentials

| Variable | Resolution | Mechanism |
|---|---|---|
| `github_app_client_id` | Deleted (var + 1 doppler_secret resource) | Zero TS/TSX consumers — `git grep` returned 0. Dead OAuth plumbing the webhook flow never uses. |
| `github_app_client_secret` | Deleted (var + 1 doppler_secret resource) | Same — zero consumers. |
| `github_actions_token` (PAT) | Deleted (var) | `provider "github"` switched to `app_auth` using existing `var.github_app_id` + `var.github_app_private_key`. Net narrowing: long-lived PAT → short-lived installation token (1-hour TTL, auto-rotated per terraform invocation). |
| `doppler_token_kb_drift` | Deleted (var) | Replaced by `doppler_service_token.kb_drift` resource — workplace-scope `DOPPLER_TOKEN_TF` (already in `prd_terraform`) authorizes the in-band mint. |

Pre-flight: mirrored `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from `prd` → `prd_terraform` so the App-auth provider can resolve them via `--name-transformer tf-var`. One-time value move, no new credentials.

One non-obvious side effect: the App needed `Repository Secrets: Read and write` permission added to its declared permissions, AND the installation needed to accept the new permission. Both were one-time browser actions (no GitHub API for App-permission self-modification) handled via Playwright in the PR session.

## Prevention — `hr-tf-variable-no-operator-mint-default`

Added to `AGENTS.core.md`:

> New TF sensitive variables must prefer provider-side mint (`doppler_service_token`, `random_id`, `app_auth`) or credential reuse over operator-mint.

PR reviewers verify the autonomy hierarchy was considered. The rule's existence catches the next operator-mint anti-pattern at PR-author time, not three weeks later at apply time.

## Key insight

The cheapest path at PR-write time is rarely the cheapest path at lifecycle level. A `variable { sensitive = true }` block is 5 lines of HCL; the operator-onboarding runbook to feed it is 50; the recurring debt across CI runners + drift detectors + new contributors is unbounded.

The corollary: **if a vendor's API can mint the credential and your TF provider has scope to call it, the credential should be a resource, not a variable.** The few exceptions (CAPTCHA-gated registrations, payment cards, hardware MFA) are exactly the operator-only canonical-list class enumerated in `2026-05-15-operator-only-step-canonical-list.md`.

## Session Errors

Errors and recoveries from the one-shot session that produced this PR. Each carries a `**Prevention:**` line so the next session can avoid the same trap.

1. **App-permission mapping wrong in initial brief.** I asserted `administration:write` was the GitHub API scope `github_actions_secret` resources require. Actual scope is `secrets:write`. The plan-deepen subagent's Phase 0.2 verification (`gh api apps/soleur-ai --jq '.permissions'`) caught it before code edits, but only after I had already authorized the refactor based on the wrong assumption. **Recovery:** drove the App permission update via Playwright mid-execution (added `secrets:write`, accepted on installation 122213433). **Prevention:** when proposing a switch from PAT auth → App-installation auth on `integrations/github`, always probe `gh api apps/<slug> --jq '.permissions'` BEFORE writing the brief. Map the PAT's API surface to the App's permission keys explicitly — `github_actions_secret` requires `secrets:write` (Actions Secrets API), NOT `administration:write` (Repo Administration API).

2. **Playwright MCP browser tearing down between tool calls.** First two attempts to drive the App-permission update via Playwright crashed before MFA could complete — the Chromium context closed when no tool was actively running. **Recovery:** the user restarted the MCP server; I switched to `browser_wait_for { text: <post-login marker>, time: 300 }` as the next tool call after `browser_navigate`, which kept the playwright connection alive during the user's MFA flow. **Prevention:** when handing off an interactive flow (login + MFA, captcha, hardware MFA) to the user inside Playwright MCP, always chain `browser_navigate` → `browser_wait_for { text: <stable post-action marker>, time: 300 }` in immediately-sequential tool calls. Do NOT pause between calls expecting the user to signal "ready" — the session may not survive the idle.

3. **Parallel `browser_navigate` + `browser_wait_for` race.** Fired both in a single parallel-tool-call block; `wait_for` ran before the page was created and returned "No open pages available." **Recovery:** re-issued as two sequential tool calls. **Prevention:** Playwright MCP tool calls have implicit page-creation ordering — calls that depend on a page existing (`browser_wait_for`, `browser_snapshot`, `browser_evaluate`) MUST run in tool calls strictly AFTER the `browser_navigate` that creates the page. Never parallelize navigate with downstream interactions.

4. **GitHub Actions workflow Edit blocked by PreToolUse security hook (advisory).** First edit attempt removing two `-target=doppler_secret.github_app_client_*` lines from `apply-web-platform-infra.yml` triggered the security_reminder_hook with the standard workflow-injection warning. Hook was advisory (not deny). **Recovery:** the second Edit attempt in the same response succeeded; hook fired once per session. **Prevention:** when editing `.github/workflows/*.yml`, expect a one-time PreToolUse advisory message on the first edit of the file in a session. Treat as informational, retry.

5. **Incomplete Doppler delete (missed `GITHUB_APP_CLIENT_SECRET`).** Batch-deleted `GITHUB_APP_CLIENT_SECRET DOPPLER_TOKEN_KB_DRIFT` together but only the LATTER was a fresh write; the former had pre-existed in prd_terraform and survived the first pass. AC6 sweep caught it. **Recovery:** explicit `doppler secrets delete GITHUB_APP_CLIENT_SECRET` second pass. **Prevention:** after a batched `doppler secrets delete A B C ...`, always re-run the inventory check (`doppler secrets -p X -c Y --only-names | grep -E 'A|B|C'`) — Doppler CLI does NOT fail loudly when a name doesn't exist; it silently succeeds for the names it found.

6. **AGENTS.core.md byte budget exceeded.** Initial new rule body (533 bytes) pushed `B_ALWAYS` from 22019 → 22552 vs the 22000-byte harness ceiling. `lint-agents-rule-budget.py` REJECTed at commit. **Recovery:** trimmed rule to 213 bytes AND demoted `wg-when-closing-a-phase-milestone-update` from `AGENTS.core.md` → `AGENTS.rest.md` (the latter is documented as the canonical escape valve). Final `B_ALWAYS` = 21893 (under ceiling). **Prevention:** when authoring a new AGENTS.core.md rule, check `B_ALWAYS` headroom BEFORE writing: `B_INDEX=$(wc -c < AGENTS.md); B_CORE=$(wc -c < AGENTS.core.md); echo "$((22000 - B_INDEX - B_CORE)) bytes free"`. If headroom < 400 bytes, plan the demotion candidate concurrently with the new rule. The lint catches it but the recovery cost is non-trivial.

7. **Workflow header `-target=` count drifted (67 → 66 missed).** Edited the workflow's target list (net -2 + 1 = -1) but left the header comment claiming "67 explicit targets." Code-quality reviewer caught it (would have); I pre-empted via grep before review fired. **Recovery:** `grep -cE '^              -target=' <workflow>` + direct edit. **Prevention:** documented under existing rule `cq-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts` (work skill Sharp Edges). This session re-confirms the pattern: any header comment carrying a count of resources/targets/anything-the-diff-changes must be re-derived from the as-written file post-edit, not from mental arithmetic.

8. **Forwarded from plan-deepen subagent.** `awk '/^## Observability/,/^## /'` self-matched only the heading line. **Recovery:** corrected the next-section heading as the range terminator. **Prevention:** documented in plan skill's Sharp Edges.

## References

- Plan: `knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md`
- Sibling pattern (Inngest IaC, same autonomy reasoning): `apps/web-platform/infra/inngest.tf`
- Doppler service-token provider docs: <https://registry.terraform.io/providers/DopplerHQ/doppler/1.21.2/docs/resources/service_token>
- App-installation auth on integrations/github: <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>
- Canonical TF invocation: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Operator-only canonical list (the legitimate exceptions): `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`
