---
title: "security: retire the dead SUPABASE_PAT — migrate postgrest-reload-schema.sh to SUPABASE_ACCESS_TOKEN and make a rejected credential fail loudly"
date: 2026-09-13
slug: security-retire-dead-supabase-pat
branch: feat-one-shot-8028-supabase-pat-retire
issue: 8028
closes: 8028
type: security
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# security: retire the dead `SUPABASE_PAT`, migrate the PostgREST reload to `SUPABASE_ACCESS_TOKEN`, fail loudly on a rejected credential

## Overview

The PostgREST schema-reload script authenticates to the Supabase Management API with a personal access token that every Doppler config now rejects. Because the migration runner invokes the script in its soft-fail mode, the rejection is reported as a warning and the reload never happens; nothing pages. This plan moves the script onto the one Management-API token that still works, makes a rejected credential a hard failure of a migration run that applied something, retires the dead token from every config that inherits it, and sweeps the remaining repo references so the retired name has no surviving consumer.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec file exists under `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/` on this branch.

**Plan-review revision (v2, 2026-09-13).** Six reviewers (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO-devex) plus a scoped advisor consult. Applied: hardening narrowed to `401|403` only (the `404`/`422`/`429` expansion and its tests cut); runner tests folded into the existing schema-probe harness (no new test file); lint-duplicating tests cut; the hook now runs on **every** migration run so a re-run after a credential fix actually reloads; `401|403` with a non-JSON body classified transient (an edge/WAF 403 must not block a release); Phase 3 loop made errexit-safe with a Doppler positive control and an empty-token guard; observability channels corrected (Resend email, not Sentry/Slack); operator-facing error text; enumerated-config prose replaced by "prd root (inherited)". **Removed on a security finding:** the `tenant-integration.yml` token injection — that workflow runs on `pull_request`, so an account-scoped, prd-reaching credential would be handed to PR-authored code (`hr-dev-prd-distinct-supabase-projects`); the same holds for copying the value into Doppler `dev`/`dev_scheduled`. Dev CI therefore keeps the script's absence-soak (warning), which is a User-Challenge to the two arms the operator offered and is recorded in `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (probed 2026-09-13) | Plan response |
|---|---|---|
| "dead (401) in all **4** Doppler configs that carry it"; `prd_scheduled` row reads "(present)", unprobed | Present and **401** in all five named configs — and, because `dev_scheduled`, `dev_personal` and the six `prd_*` configs are Doppler **branch configs** inheriting from the `dev`/`prd` roots, present in **ten** of the project's thirteen configs (`ci`, `cli`, `cli_ops` never carried it). One identical value everywhere (sha256 prefix match) — the signature of root inheritance. | Delete at the two roots, then verify every branch config (delete only a branch-level override); assert absence across all thirteen. |
| `SUPABASE_ACCESS_TOKEN` "works and reaches all 3 projects", present in `prd`, `prd_terraform`; `prd_scheduled` "(present)" | Present and 200 in the `prd` root and all six `prd_*` branches (inherited) — one identical value. Absent in every `dev`-environment config. Also a GitHub Actions repo secret (Terraform-published). | Script reads `SUPABASE_ACCESS_TOKEN`. No copy into any `dev` config (see the security finding in the Overview). |
| "every workflow under `.github/workflows/apply-inngest-rls*.yml`, `scheduled-supabase-advisor-scan.yml` etc. uses" `SUPABASE_ACCESS_TOKEN` | Confirmed — and every one of those triggers on `push`/`schedule`/`workflow_dispatch`, **never `pull_request`**. | Do not extend that pattern to `tenant-integration.yml` (a `pull_request` job). |
| The consumer authenticates "at `:138`" and takes the `fail_or_skip 2 "auth rejected …"` branch "at `:159`" | Anchors hold (the `--header "Authorization: Bearer ${SUPABASE_PAT}"` line and the `401|403)` case arm). | Both are edit sites; cited by content, not line, below. |
| Consumer count implied: one script | Consumers: the script, its test, and a comment in `run-migrations.sh`. Actionable docs: `migration-rollback.md`, the credential-rotation runbook, `secret-scanning.md`'s rotation entry, the 2026-05-21 learning's §Prevention (which instructs re-minting the dead PAT). Detector/historical: the deprecated-endpoints lint regex + allowlist, `scrub-supabase-pat.sh` prose, ADR-197, ADR-216, three learnings, a community digest, a `work` SKILL.md sharp edge. | Sweep the consumers and actionable docs; leave detector regex and historical records. |

## Research Insights

### Premise Validation (Phase 0.6)

- **Issue #8028** — `gh issue view 8028 --json state,closedByPullRequestsReferences` → `OPEN`, no closing PR. Premise holds.
- **Cited file paths** all exist on this branch: `apps/web-platform/scripts/postgrest-reload-schema.sh`, `apps/web-platform/scripts/postgrest-reload-schema.test.sh`, `apps/web-platform/scripts/run-migrations.sh` (invokes the hook with `--best-effort` under `if [[ "$applied" -gt 0 ]]`).
- **Live external state, probed 2026-09-13** (values never printed; presence via `doppler secrets get <name> … --plain >/dev/null`, liveness via `curl -s -o /dev/null -w '%{http_code}' --max-time 15 --header @- https://api.supabase.com/v1/projects` with the bearer on stdin):

  | Doppler config | `SUPABASE_PAT` | `SUPABASE_ACCESS_TOKEN` |
  |---|---|---|
  | `soleur/dev` (root) | present, **401** | absent |
  | `soleur/dev_personal`, `soleur/dev_scheduled` (branches of `dev`) | present (inherited), **401** | absent |
  | `soleur/prd` (root) | present, **401** | present, 200 |
  | `soleur/prd_cla`, `prd_ghcr`, `prd_kb_drift_walker`, `prd_scheduled`, `prd_terraform`, `prd_workspaces_luks` (branches of `prd`) | present (inherited), **401** | present (inherited), 200 (`prd_terraform`'s first probe hit a curl timeout `000`; re-probe 200) |
  | `soleur/ci`, `soleur/cli`, `soleur/cli_ops` | absent | absent |

  Both tokens are `sbp_`-prefixed, 44 chars — the existing `scrub_pat` regex (`sbp_[A-Za-z0-9]{20,}`) covers the replacement token unchanged. The GitHub Actions repo secret `SUPABASE_ACCESS_TOKEN` exists (`gh secret list`, updated 2026-06-18), written by `github_actions_secret.supabase_access_token` in `apps/web-platform/infra/inngest.tf` from `var.supabase_access_token` (Doppler `prd_terraform`). Neither token is a Terraform-managed `doppler_secret` (`git grep 'resource "doppler_secret"' -- 'apps/web-platform/infra/*.tf'` names no `SUPABASE_*`), so a CLI delete creates no drift.
- **Doppler topology** (`doppler configs -p soleur --json`): roots are `dev`, `ci`, `prd`, `cli`; the others are branch configs (`root=false`). `doppler secrets get <missing> --plain` exits **1** — and so does a missing/unreadable config or a revoked CLI token (Kieran, verified), which is why the retirement loop carries a positive control.
- **Live token reaches every project ref the script can resolve** (read-only, `prd_terraform` value, bearer on stdin): `GET /v1/projects/{ref}` → 200 for `mlwiodleouzwniehynfz` (dev; `NEXT_PUBLIC_SUPABASE_URL` in `dev` is `https://mlwiodleouzwniehynfz.supabase.co`), `ifsccnjhymdmidffkzhl` (prd web-platform; `prd` URL is the custom domain `https://api.soleur.ai`, resolved by the script's CNAME fallback), `pigsfuxruiopinouvjwy` (prd inngest).
- **The GH Actions secret value is live**: `scheduled-supabase-advisor-scan.yml`, which authenticates with `${{ secrets.SUPABASE_ACCESS_TOKEN }}`, concluded `success` on 2026-09-11, -12 and -13 (`gh run list`). Recorded for completeness — this plan no longer routes any job through that secret.
- **`doppler run` ambient-env passthrough** verified (`FOO_PROBE_8028=yes doppler run -p soleur -c dev -- printenv FOO_PROBE_8028` → `yes`): the local-operator invocation below relies on it.
- **`doppler secrets delete` CLI form** verified via `--help`: `doppler secrets delete [secrets] -p <project> -c <config> --yes` (`-y, --yes  proceed without confirmation`).
- **ADR corpus grep** for the proposed mechanisms (`best-effort`, `soft-fail`, `account-scoped`, `SUPABASE_ACCESS_TOKEN`): no ADR rejects hardening a soft-fail branch or names token placement. ADR-197 records that `scripts/lint-supabase-deprecated-endpoints.sh`'s host-pin arm is keyed on files matching `/v1/projects|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`; ADR-216 cites "a dead `SUPABASE_PAT`" as an example of a live incident that reads like machinery. Neither constrains the design beyond "make it observable".

### Property List and Cut List (Phase 0.6b)

**Properties (observable outcomes the ask is for):**

- P1 — After a migration apply in prd (and when an operator runs the script by hand), the PostgREST schema reload is actually acknowledged by the Management API (HTTP 2xx), because the script authenticates with a credential the API accepts.
- P2 — A credential the Management API rejects (401/403 with an API response body) produces a non-zero script exit and a job-visible failure of any migration run that applied something — never a soft skip, regardless of `--best-effort`.
- P3 — An environment that never opted in (no token / no project URL — the local Supabase stack in `rls-authz-fuzz.yml`, and dev CI, which must not hold a prd-reaching credential) still does not fail its migration run under `--best-effort`; transient upstream failure is still soaked.
- P4 — No Doppler config carries `SUPABASE_PAT` afterwards, and no tracked file names it as a consumer (historical mentions in learnings/ADRs/archives may remain).
- P5 — The account-scoped Management-API token is not copied into any additional Doppler config or `pull_request`-triggered job; the credential surface shrinks (10 configs carrying a dead account-scoped token → 0; the live one stays in the `prd` root + its inherited branches + the one GH secret).
- P6 — The fail-loud behaviour is verifiable locally (shell test suites) and in CI without SSH.

**Mechanisms → property → coverage on `origin/main`:**

| Mechanism | Buys | Already covered? | Disposition |
|---|---|---|---|
| Rename script/test/header env var to `SUPABASE_ACCESS_TOKEN` | P1, P4 | No | Keep |
| `401\|403` (JSON body) exits 2 under `--best-effort`; runner propagates when `applied > 0` | P2 | No — `fail_or_skip` has no durable arm; `run-migrations.sh` converts any hook non-zero into `::warning` | Keep; needs both the script and the caller |
| Run the hook on every migration run (not only when `applied > 0`) | P2 (re-run after a credential fix reloads instead of dead-ending) | No | Keep (spec-flow P1) |
| Delete `SUPABASE_PAT` at the `dev`/`prd` roots, verify all thirteen configs | P4, P5 | No | Keep (work-phase, pipeline-performed) |
| Repo-wide grep sweep (`':!*.json'`) | P4 | No | Keep |
| xtrace preamble + `curl --disable --noproxy '*' --header @-` | none of P1–P6 directly | Forced: the shell-trace credential lint runs `--changed` in CI and bypasses the baseline for a touched file (2 findings today) | Keep (lint-mandated) |
| **Copy the prd `SUPABASE_ACCESS_TOKEN` into Doppler `dev`/`dev_scheduled`** (operator-offered arm) | P1 in dev CI | — | **Cut** — `dev_scheduled` is read by a `pull_request` job; violates P5 and `hr-dev-prd-distinct-supabase-projects` |
| **Inject `secrets.SUPABASE_ACCESS_TOKEN` as step env in `tenant-integration.yml`** (v1 of this plan) | P1 in dev CI | — | **Cut** (architecture P0) — same exposure; every existing consumer of that secret is `push`/`schedule`/`workflow_dispatch`-only |
| Harden `404`/`422`/other 4xx and carve out `429` (v1) | none named — P2 names 401/403 | — | Cut (simplicity P1; both panels fired on the scope) |
| Separate `run-migrations-reload-hook.test.sh` (v1) | P6 | Yes — `run-migrations-schema-probe.test.sh`'s `make_temp_tree` already relocates the runner with a fake `psql` | Cut; the cases go into that harness |
| T18/T19 (`bash -x` → 78; `--disable` first) (v1) | lint hygiene | Yes — `lint-shell-trace-credential-refusal.py --changed` fails the PR on either | Cut |
| Mint a replacement `SUPABASE_PAT` | P1 | Yes — `SUPABASE_ACCESS_TOKEN` is the same class of token and already works | Cut (the issue's own recommendation) |
| Direct Sentry mirror from the bash hook | P2 observability | Yes for prd — `release-outcome` emails the non-delivery (Resend) with a Sentry fallback | Cut |
| Migrate the inline `scrub_pat` to `scripts/lib/scrub-supabase-pat.sh` | none | The lib header explicitly defers migrating pre-existing copies | Cut |
| Vendor-side revocation of the dead PAT | nothing — already 401 at the vendor | n/a | Cut; state it in the PR body |

### Codebase findings

- `apps/web-platform/scripts/postgrest-reload-schema.sh` — usage header (`Required environment:` block, `Examples:`, and the `--best-effort` flag description), `scrub_pat`, `fail_or_skip`, the `if [[ -z "${SUPABASE_PAT:-}" ]]` precondition, the `--header "Authorization: Bearer ${SUPABASE_PAT}"` curl line, and the `401|403)` case arm are the edit sites. Exit-code contract in the header: 0 ok / 1 transient / 2 auth-or-config. `DOPPLER_CONFIG` is injected by `doppler run` (precedent: `apps/web-platform/scripts/seed-dev-users.sh` refuses unless it equals `dev`), so an error message can name the config the credential came from.
- `apps/web-platform/scripts/run-migrations.sh` — the post-apply block (`# Post-apply: force a PostgREST schema-cache reload`) runs `bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort` inside `if [[ "$applied" -gt 0 ]]` and `if ! …; then echo "::warning title=PostgREST schema reload hook failed::…"; fi`, with a comment asserting "any non-zero exit it returns is itself a bug in the script". That comment becomes false under the new contract and must change with the code. `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, so a relocated runner looks for the hook next to itself. The runner has no `trap`; the hook block is its last statement, so a propagated `exit` becomes the step status in both workflow callers (Kieran, verified).
- Callers of `run-migrations.sh` and the env each runs under: `web-platform-release.yml` `migrate` job (`doppler run -c prd`; `deploy` `needs: [resolve-target, migrate, verify-migrations, verify-doppler-secrets]`; `release-outcome` `needs:` all of them, `classify migrate` maps `failure|cancelled` to non-delivery, and delivers by **Resend email to ops@** with a Sentry event only when `steps.email.outputs.delivered != '1'`; `notify-gated` keys on `resolve-target.skip_reason` / CI conclusion and never fires for a `migrate` failure), `tenant-integration.yml` "Apply migrations to dev" (`doppler run -p soleur -c dev_scheduled -- bash scripts/run-migrations.sh --bootstrap=skip`; triggers `push` to main + **`pull_request`**, PR merge ref checked out; the only `secrets.*` referenced is `DOPPLER_TOKEN_DEV_SCHEDULED`, hard-checked in "Verify DOPPLER_TOKEN_DEV_SCHEDULED is provisioned"), `rls-authz-fuzz.yml` (local stack, bare `bash scripts/run-migrations.sh --bootstrap=skip`, no `NEXT_PUBLIC_SUPABASE_URL` in the job).
- `scripts/rotate-supabase-db-credential.sh` — `TOKEN_CONFIG=prd_terraform` / `TOKEN_NAME=SUPABASE_ACCESS_TOKEN   # SUPABASE_PAT is dead (401) everywhere -- #8028`: the precedent for reading the live token from `prd_terraform` regardless of the target config; also the precedent for the #7797 xtrace-refusal preamble.
- `scripts/lint-shell-trace-credential-refusal.py` (#7797, #7873) runs in CI as `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`, and in `--changed`/explicit-path mode **bypasses both baselines** (`scoped = args.changed or args.paths; baseline = set() if scoped …`). `postgrest-reload-schema.sh` is listed in `scripts/lint-shell-trace-credential-refusal.baseline.txt` and `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`; run explicitly today it reports **2 violations**: Rule A ("binds a live credential but carries no xtrace refusal") and Rule D at the curl line ("missing `--disable` as its FIRST argument … and `--noproxy '*'`"). **Probe-first result:** a scratch copy carrying the #7797 preamble (`case "$-" in *x*) … exit 78 ;; esac` immediately after `set -euo pipefail`) and `printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" | curl --disable --noproxy '*' --silent --show-error --request POST --url "$endpoint" --header @- …` reports `OK: 1 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`. Model file named by the lint: `scripts/supabase-logs-query.sh` `api_get()`. The lint has `--write-baseline` and `--write-baseline-d` (full-tree regeneration). `run-migrations.sh` is not baselined and passes today.
- `scripts/lint-supabase-deprecated-endpoints.sh` — host-pin assembly is `git grep -lIE -e '/v1/projects|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT'`; the script stays a member via `SUPABASE_ACCESS_TOKEN` + `/v1/projects` and still carries the bare `https://api.supabase.com` literal, so membership is unchanged. Allowlist entry `'apps/web-platform/scripts/run-migrations.sh|2026-08-26|comment about a missing SUPABASE_PAT never failing the run; delegates to postgrest-reload-schema.sh, which is pinned'` — `run-migrations.sh` remains a member only through comment/message text naming the token, so the reason string must be refreshed. `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` today: `OK — census 28 (baseline 26)` with a pre-existing note (unrelated). The lint's own `SUPABASE_PAT` regex token is a detector, not a consumer, and is deliberately left (ADR-197) with a one-line comment so nobody "cleans it up".
- `plugins/soleur/test/fixture-relative-assert.test.sh` keeps a **row-by-row equality** baseline (`fixture-relative-assert.baseline.txt`: a fall reddens exactly like a rise) with rows for `postgrest-reload-schema.test.sh` (1), `run-migrations-schema-probe.test.sh` (3), `run-migrations.sh` (1). Edits that change the count of not-provably-absolute operands require `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` in the same commit.
- `scripts/test-all.sh` registers `apps/web-platform/scripts/*.test.sh`; `bash scripts/lint-orphan-test-suites.sh` enforces registration. `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → **15 passed, 0 failed** today (T1–T14 incl. T13b; ~1 s). Tests use a PATH-shimmed fake `curl` that records argv to `$CURL_ARGS_FILE` and renders `$CURL_BODY\n$CURL_HTTP_CODE`; T4/T14 grep argv for the endpoint and (T4) for `Authorization: Bearer sbp_fake`; T11 asserts the token does not leak into the error path; T5/T12 assert `rc == 2` on 401/404 (so a fake curl that stops rendering the status code — catch-all exit 1 — reddens them).
- `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` — `make_temp_tree` copies the runner to `$tmp/scripts/run-migrations.sh` with a fake `psql` (unquoted heredoc, canned responses keyed on SQL substrings) and a `099_test_missing_ref.sql`; its probe-OFF case reaches the apply phase (`applied=1`) and therefore invokes `$tmp/scripts/postgrest-reload-schema.sh`, which the harness never plants. **Reproduced by hand:** the runner prints `bash: …/scripts/postgrest-reload-schema.sh: No such file or directory` (rc 127) followed by `::warning title=PostgREST schema reload hook failed::…` and exits 0. Under the new propagate-the-hook contract that case would exit 127, so the harness must plant a stub hook. 5 passed today, ~6 s.
- Repo sweep `git grep -n SUPABASE_PAT -- . ':!*.json'` (excluding `knowledge-base/project/{plans,specs}`): consumers = the script, its test, `run-migrations.sh` (comment). Actionable docs = `apps/web-platform/docs/migration-rollback.md` ("Requires `SUPABASE_PAT` in Doppler"), `knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` (`## Token`), `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` §Prevention 3 (prescribes minting the PAT and storing it under `SUPABASE_PAT`). Rotation runbook `knowledge-base/engineering/operations/secret-scanning.md` `### SUPABASE_ACCESS_TOKEN (CLI / sbp_)` lists only `prd_terraform` + `~/.zshrc` (stale: the value is inherited by every `prd_*` branch and is TF-published to the GH secret). Detector/lib/historical = `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/lib/scrub-supabase-pat.sh` (file name and header prose only), `scripts/rotate-supabase-db-credential.sh` (comment already correct), ADR-197, ADR-216, three learnings, `knowledge-base/support/community/2026-05-22-digest.md`, `plugins/soleur/skills/work/SKILL.md` (a Sharp Edge narrating #7966). `variables.tf` declares only `supabase_access_token` (no `TF_VAR_supabase_pat`); no other Doppler branch config has a consumer that runs `run-migrations.sh` (architecture-strategist, verified).
- Constitution (`knowledge-base/project/constitution.md`) shell conventions: `#!/usr/bin/env bash` + `set -euo pipefail`; `local` variables; error messages to stderr; operator-protection signals to stdout (the script's `::error::`/`::warning::` annotations go to stderr today, which GitHub Actions still renders as annotations — unchanged by this plan); `[[ ]]` tests; `# --- Section ---` headers.

### Institutional learnings applied

- `knowledge-base/project/learnings/security-issues/2026-05-26-doppler-secrets-delete-dumps-full-config-to-stdout.md` — `doppler secrets delete … --yes` prints the entire remaining config table; always `> /dev/null` and verify separately.
- `knowledge-base/project/learnings/2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md` — a Management-API 401 is often a validation/scope signal; the script's rejection message keeps printing the response body and says so.
- `knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md` and `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md` — the dead PAT is the canonical example of a defect a green suite could not see; the new tests fixture the *dead-but-present* case explicitly and the guard contract lists mutations that redden the suite. The same class drives the Phase 3 positive control: `doppler secrets get` exits 1 for "absent" *and* for "Doppler unreachable", so an absence check alone would print thirteen `absent` lines on a revoked CLI token.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the mutation matrix is written here, before the code.
- `knowledge-base/project/learnings/2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` — only `${{ secrets.* }}` values are auto-masked; no token reaches a PR job under this plan; the script never echoes the token (T11) and scrubs `sbp_` shapes from every message.
- `knowledge-base/project/learnings/2026-05-16-repo-research-must-inventory-scheduled-ci-workflows-for-secret-sweeps.md` — CI workflows were inventoried, not just runtime configs; the inventory is what surfaced `tenant-integration.yml`'s `pull_request` trigger.
- `knowledge-base/project/learnings/best-practices/2026-04-22-plan-ac-external-state-must-be-api-verified.md` — Doppler state was probed via the API at plan time, not inferred from code.
- `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` — origin of the script and of the `--best-effort` rationale ("a missing PAT or transient upstream issue cannot fail the migration run"): the plan preserves exactly that and narrows it to *missing* and *transient*.

### Related issues and PRs

- #8028 (this issue); #4285 / PR #4286 (script origin); PR #4320 (custom-domain CNAME fallback, ref echo, endpoint pin); #7797 / PR #7793 (xtrace refusal lint); #7873 (Rule D transport confinement); #7966 (credential-rotation session that found the dead PAT); #3364 (open code-review issue touching `run-migrations.sh` — see Overlap section).

## Problem Statement / Motivation

`postgrest-reload-schema.sh` is the only path by which a migration applied over the IPv4 session-mode pooler reaches PostgREST's schema cache before its ~10-minute natural poll (learning 2026-05-21 §1). It reads `SUPABASE_PAT`, which the Management API has rejected with 401 in every config since at least 2026-09-10. `run-migrations.sh` invokes it with `--best-effort`, whose contract is "missing PAT or transient upstream issue must not break the migration run" — but the implementation soaks *every* failure class, including a present-and-rejected credential. Net effect: every prd release that applies a migration prints a `::warning::` nobody reads, and supabase-js against a freshly-added table returns `PGRST205` for up to ten minutes. Two account-scoped tokens with identical scope also exist where one suffices.

## Proposed Solution

Four decisions, each justified against the property list:

1. **Token: `SUPABASE_ACCESS_TOKEN`, no new mint.** It is the same token class (`sbp_` PAT), already the credential of every other Management-API consumer in the repo, already published to GitHub Actions by Terraform, and it is the env var name the Supabase CLI itself reads. Minting a second account-level token restores a redundant credential the issue exists to remove.

2. **Semantics: `--best-effort` soaks absence and transience, never a rejection.** The mode keeps exit 0 + `::warning::` for: `curl` not on PATH, `SUPABASE_ACCESS_TOKEN` unset, `NEXT_PUBLIC_SUPABASE_URL` unset or unparseable, curl rc ≠ 0, HTTP 5xx, HTTP 000/non-numeric, HTTP 404/other 4xx (unchanged from main), and a 401/403 whose body is **not** a Management-API JSON error (an edge/WAF challenge page — transient, exit 1 in strict mode). A 401/403 **with a JSON body** (`{`-prefixed) is the API rejecting the credential: the script exits 2 with `::error::` **even under `--best-effort`**. `run-migrations.sh` now runs the hook on **every** migration run and propagates a non-zero hook exit only when `applied > 0` (otherwise `::warning`), so a re-run after a credential fix reloads the cache instead of dead-ending at `applied=0`. In prd a red `migrate` blocks `deploy` (old code keeps running against a backward-compatible schema — no user-visible error) and `release-outcome` emails the non-delivery. The alternative — deploy anyway — trades a delayed release for up to ten minutes of `PGRST205` 500s on every feature touching a new table, for real users, with no rollback lever (`hr-weigh-every-decision-against-target-user-impact`).

3. **Dev token sourcing: none in CI; `prd_terraform` on demand for operators; absence stays soft.** `tenant-integration.yml` runs on `pull_request` with the PR's merge ref checked out, so any credential it holds is available to PR-authored SQL and shell. Neither offered arm is safe: copying the account-scoped token into Doppler `dev`/`dev_scheduled` is read by that same job, and injecting the GH secret as step env (v1 of this plan) has the same effect; every existing consumer of `secrets.SUPABASE_ACCESS_TOKEN` is `push`/`schedule`/`workflow_dispatch`-only for exactly this reason. Supabase exposes no project-scoped Management-API credential (`variables.tf`), so there is no narrower token to give it. Dev CI therefore keeps the script's absence-soak: `::warning::` and the ~10-minute natural poll — the state it has been in since the PAT died, minus the lie that a credential was tried. Operators running the script locally read the token on demand from `prd_terraform` (the `rotate-supabase-db-credential.sh` precedent); the script's `--help` carries that one-liner as the single copy-pasteable source. Recorded as DC-1 in `decision-challenges.md` because it declines both arms the operator named.

4. **Retirement: pipeline-performed, roots first, every config verified.** The dead token lives in ten configs because the eight branch configs inherit it from the `dev` and `prd` roots. In the work phase: for each root, confirm Doppler is reachable (positive control on the built-in `DOPPLER_CONFIG`), confirm the name is present, probe it against `GET /v1/projects` and **refuse on anything but 401/403**, for `prd` additionally confirm `SUPABASE_ACCESS_TOKEN` is present (the config the script is used from — operator-requested check), then delete; re-verify every branch config, deleting only a branch-level override; finally assert absence across all thirteen. `doppler secrets delete … --yes > /dev/null` (the command dumps the whole config to stdout), bearer on stdin for every probe, presence via `doppler secrets get … --plain`'s exit code. No operator checklist. The token is already dead at the vendor, so no dashboard revocation step exists to automate.

Touching the script also forces two hardenings the shell-trace credential lint demands of any changed file: the #7797 xtrace-refusal preamble and `curl --disable --noproxy '*' --header @-` with the bearer on stdin (token no longer in curl argv). Both baselines are regenerated with the lint's own `--write-baseline` / `--write-baseline-d`.

## Technical Considerations

- **Exit-code capture in the caller.** `if ! cmd; then rc=$?` yields `0`. Use the errexit-safe idiom `hook_rc=0; bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`.
- **`--header @-` reads the header from stdin** (curl ≥ 7.55; local 8.18, `ubuntu-latest` 8.x; production precedent `scripts/supabase-logs-query.sh`). Inside `response="$(printf … | curl …)"` under `set +e` with `pipefail` on, the status is curl's (Kieran, verified with real curl). The fake curl in the test must `cat` stdin so T4 can assert the header arrived there and is absent from argv; every `bash "$SCRIPT"` invocation in the test gets `</dev/null` so the RED phase cannot block on a tty.
- **`--disable` must be curl's first argument** (aborts `~/.curlrc` parsing); `--noproxy '*'` neutralises `ALL_PROXY`/`HTTPS_PROXY` redirection of the pinned destination. Rule D scans destinations positionally; `endpoint="https://api.supabase.com/…"` is a pinned literal and passes (probe verified).
- **JSON-body discrimination for 401/403.** `[[ "$body" == \{* ]]` — the Management API returns `{"message": …}`; a Cloudflare challenge returns HTML or nothing. No `jq` dependency.
- **`scrub_pat` stays named `scrub_pat`**: the replacement token *is* a PAT. Only the environment variable name changes.
- **Hook on every run.** A `NOTIFY pgrst, 'reload schema'` on a no-op run is harmless and doubles as a per-run liveness check of the credential (a dead token now surfaces as a `::warning::` on every prd release and as `::error::` + red job on the first release that applies a migration).
- **Transient 403.** A non-JSON 403 is soaked; a JSON 403 that is nonetheless transient costs one job re-run — and the re-run now reloads (decision 2).
- **`verify-migrations`** (`needs: [resolve-target, migrate]`) is skipped when `migrate` fails; any `follow-through` issues it would auto-close stay open until the re-run — acceptable (CTO).
- **Learning-file edit.** Learnings are point-in-time records, but §Prevention 3 of the 2026-05-21 learning is runbook-shaped and instructs re-minting the dead token; it gets a dated `[Updated 2026-09-13 — #8028]` correction, not a rewrite.
- **Enumerated-config prose rots.** Docs say "Doppler `prd` root (inherited by every `prd_*` branch)", never a list of branch names (CTO).

### Attack Surface Enumeration (for security fixes)

| Surface | Before | After |
|---|---|---|
| Account-scoped Supabase Management-API tokens in Doppler | `SUPABASE_PAT` (dead) in 10 configs + `SUPABASE_ACCESS_TOKEN` (live) in the `prd` family (7) | `SUPABASE_ACCESS_TOKEN` in the `prd` family only; nothing account-scoped in any `dev`-environment config |
| Credential reachable from a `pull_request` job | none | none (v1's injection removed) |
| Token in curl argv (`ps`-visible for the call's lifetime) | yes | no — `--header @-` from stdin |
| Token echo via `bash -x` | possible | refused (exit 78 preamble) |
| Proxy-env redirect of the pinned POST | possible via `ALL_PROXY`/`HTTPS_PROXY` | neutralised (`--noproxy '*'`) |
| `~/.curlrc` injection of flags | possible | neutralised (`--disable` first) |
| Silent auth failure | soaked as `::warning::` | red job + `::error::` on any run that applied a migration; `::warning::` on no-op runs |

## Files to Edit

- `apps/web-platform/scripts/postgrest-reload-schema.sh` —
  - xtrace preamble immediately after `set -euo pipefail` (copy the `rotate-supabase-db-credential.sh` shape: `case "$-" in *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;; esac`);
  - header `Required environment:` → `SUPABASE_ACCESS_TOKEN` (the Supabase CLI's canonical `sbp_` PAT; lives in the Doppler `prd` root, inherited by every `prd_*` branch, and in the GH Actions secret; **no `dev` config carries it by design**);
  - header `Examples:` → the two working forms: `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` and the dev form `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform --plain)" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` (single copy-pasteable source; T9 asserts `-c prd_terraform --plain` is in `--help`);
  - header `--best-effort` description → "Soft-fail for ABSENCE (token/URL unset, curl missing) and TRANSIENCE (network, 5xx, non-JSON 401/403): exits 0 with a stderr warning. A credential the Management API rejects (401/403 with a JSON body) still exits 2 — a rejected credential never self-heals (#8028)."; `Exit codes` wording adds "(2 is returned under --best-effort too for a rejected credential)";
  - precondition `if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]` with message `SUPABASE_ACCESS_TOKEN is not set (Doppler config '${DOPPLER_CONFIG:-<ambient env>}'). It lives in the prd root; for a dev target read it from prd_terraform — see --help.`;
  - curl call → `printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" | curl --disable --noproxy '*' --silent --show-error --request POST --url "$endpoint" --header @- --header "Content-Type: application/json" --data "$payload" --max-time 15 -w $'\n%{http_code}' 2>/dev/null`;
  - case arm `401|403)`: if `[[ "$body" == \{* ]]` → scrub, then `echo "::error::postgrest-reload-schema: Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP ${http_code}) from Doppler config '${DOPPLER_CONFIG:-<ambient env>}'. Rotate it per knowledge-base/engineering/operations/secret-scanning.md §SUPABASE_ACCESS_TOKEN. A Management-API 401 is often a scope/validation signal — read the body. Not skipped under --best-effort: a rejected credential never self-heals. Response: ${body}" >&2; exit 2` (this arm ignores `best_effort` — inline, one caller, no new helper); else `fail_or_skip 1 "auth endpoint answered HTTP ${http_code} without an API body (edge/WAF?). Retry. Response: ${body}"`;
  - other arms unchanged; update the `# Scrub bearer tokens` and `# Endpoint is pinned` comments to name `SUPABASE_ACCESS_TOKEN`.
- `apps/web-platform/scripts/postgrest-reload-schema.test.sh` — rename every `SUPABASE_PAT` fixture/assertion to `SUPABASE_ACCESS_TOKEN` (T1, T2, T3, T4, T5, T6, T7, T8, T9, T11, T12, T13, T13b, T14); every `bash "$SCRIPT"` invocation gets `</dev/null`; extend `make_fake_curl` to `cat > "${CURL_STDIN_FILE:-/dev/null}"` before printing; T4 asserts `Authorization: Bearer sbp_fake` in the stdin capture, `--header` followed by `@-` in argv, and the bearer **absent** from argv; T5/T12 additionally give the fake a JSON body (`CURL_BODY='{"message":"unauthorized"}'` is already T5's); T9 additionally asserts `-c prd_terraform --plain`; new **T15** (401 + JSON body under `--best-effort` → exit 2, stderr contains `::error::` and `Supabase rejected SUPABASE_ACCESS_TOKEN`, does not contain `skipping`), **T15b** (403 + JSON body under `--best-effort` → exit 2), **T15c** (403 with `CURL_BODY='<html>challenge</html>'`: strict → exit 1 with `without an API body`; `--best-effort` → exit 0 with `warn|skip`).
- `apps/web-platform/scripts/run-migrations.sh` — post-apply block becomes: run the hook unconditionally after the `Migration run complete:` line; `hook_rc=0; bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`; `if [[ "$hook_rc" -ne 0 && "$applied" -gt 0 ]]; then echo "::error title=Supabase rejected the migration credential::Migrations applied (${applied}), but the schema-cache refresh was refused (hook exit ${hook_rc}; see the error above). New tables may 404 in the app for ~10 min. Fix the token, then re-run this job — it will not re-apply migrations, but it will retry the refresh."; exit "$hook_rc"; elif [[ "$hook_rc" -ne 0 ]]; then echo "::warning title=Schema-cache refresh refused on a no-op run::Nothing was applied, so this run stays green, but the reload hook exited ${hook_rc} — the credential needs attention before the next migration."; fi`; rewrite the two preceding comments (the `--best-effort` rationale now reads "soaks a missing token/URL or a transient upstream error; a rejected credential exits 2 and is propagated when something was applied so the job goes red (#8028); the hook runs on every run so a re-run after a credential fix reloads"); delete the "any non-zero exit it returns is itself a bug" paragraph.
- `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` — `make_temp_tree` additionally writes an executable `$tmp/scripts/postgrest-reload-schema.sh` stub (`#!/usr/bin/env bash`; `touch "$(dirname "$0")/../hook-ran"`; `exit "${FAKE_RELOAD_HOOK_RC:-0}"`) with a comment naming #8028; the fake `psql` gains a `FAKE_ALREADY_APPLIED` branch so the `count(*) FROM public._schema_migrations WHERE filename` query can return `1`; new cases **R1** (probe off, apply, hook rc 0 → runner exit 0, no `::error`, `hook-ran` present), **R2** (probe off, apply, `FAKE_RELOAD_HOOK_RC=2` → runner exit 2 and output contains `::error title=Supabase rejected the migration credential::`), **R4** (`FAKE_ALREADY_APPLIED=1` so `applied=0`, `FAKE_RELOAD_HOOK_RC=2` → runner exit 0, `hook-ran` present, output contains `::warning title=Schema-cache refresh refused on a no-op run::`). Header comment updated to say the suite also covers the post-apply reload hook.
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` and `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` — regenerated via `python3 scripts/lint-shell-trace-credential-refusal.py --write-baseline` and `--write-baseline-d` (full-tree, no `--changed`); the diff must be exactly the removal of the `apps/web-platform/scripts/postgrest-reload-schema.sh` row in each.
- `scripts/lint-supabase-deprecated-endpoints.sh` — refresh the `run-migrations.sh` allowlist reason (date `2026-09-13`, "runner messages/comments name SUPABASE_ACCESS_TOKEN around the post-apply hook; delegates to postgrest-reload-schema.sh, which is pinned"); add a one-line comment beside the assembly regex: `# SUPABASE_PAT intentionally retained after #8028 — a resurrected consumer must still enter the assembly.`
- `apps/web-platform/docs/migration-rollback.md` — "Requires `SUPABASE_PAT` in Doppler" → "Requires `SUPABASE_ACCESS_TOKEN` (Doppler `prd` root, inherited by every `prd_*` branch; for a dev target read it from `prd_terraform` — run the script with `--help` for the exact one-liner)"; note that a rejected token now exits 2 even under `--best-effort` and that the migration runner retries the refresh on every run, so re-running a red migration job after rotating the token reloads the cache (#8028).
- `knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` — `## Token`: replace the present-tense "does not use `SUPABASE_PAT`, which returns HTTP 401…" with "`SUPABASE_PAT` was retired in #8028 (dead in every config); `SUPABASE_ACCESS_TOKEN` is the sole Management-API credential."
- `knowledge-base/engineering/operations/secret-scanning.md` — `### SUPABASE_ACCESS_TOKEN (CLI / sbp_)`: fan-out becomes "Doppler `prd` root (inherited by every `prd_*` branch) + the GH Actions secret via `terraform apply` of `github_actions_secret.supabase_access_token` + local exports"; add "rotation failure fails the prd migration job on the next release that applies a migration (#8028 made that loud); no `dev` config carries this token by design".
- `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` — §Prevention 3: append `[Updated 2026-09-13 — #8028]`: the token is `SUPABASE_ACCESS_TOKEN` (prd root; dev reads it from `prd_terraform`); `--best-effort` soaks only a missing token/URL or a transient error; a rejected credential exits 2 and fails a migration run that applied something. Keep the original sentences (historical record), do not re-instruct minting.

## Files to Create

None. (v1's separate runner test file was folded into `run-migrations-schema-probe.test.sh` at plan review.)

## Implementation Phases

Phases are ordered by dependency direction: the script's contract changes first, then its caller, then the live retirement, then docs. All tests are written RED first (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (work-time probes, no edits)

- `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 15 passed (baseline). `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` → 5 passed (baseline).
- `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → 2 violations (Rule A, Rule D) — the state this plan remediates.
- `curl --version | head -1` ≥ 7.55 (for `--header @-`).
- Re-run the thirteen-config presence sweep and the liveness probes from Research Insights (bearer on stdin); abort the retirement phase if any `SUPABASE_PAT` returns other than 401/403, or if `SUPABASE_ACCESS_TOKEN` from the `prd` root is not 200.

### Phase 1 — `postgrest-reload-schema.sh` + its test (RED → GREEN)

1. Add T15, T15b, T15c, the T4 stdin/argv assertions, the T9 `--help` assertion, and `</dev/null` on every invocation; run → RED on T4, T9, T15, T15b, T15c.
2. Rename `SUPABASE_PAT` → `SUPABASE_ACCESS_TOKEN` in the remaining fixtures.
3. Edit the script per Files to Edit (preamble, header, precondition message, curl form, `401|403` arm with JSON-body discrimination). Run → 18 passed.
4. `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → `OK`. Regenerate both baselines with `--write-baseline` / `--write-baseline-d`; `git diff --stat` on the two baseline files shows one removed line each; full-tree lint → clean.
5. **Exercise the exact endpoint the hard arm will judge, before flipping the caller:** `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform --plain)" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` (strict, dev project) prints `postgrest-reload-schema: reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2xx)`. A schema-cache NOTIFY on dev is harmless and proves `POST /v1/projects/{ref}/database/query` accepts this token class.

### Phase 2 — `run-migrations.sh` + harness (RED → GREEN)

1. Plant the stub hook and the `FAKE_ALREADY_APPLIED` branch in `make_temp_tree`; add R1, R2, R4; run → still 5 existing passes, RED on R2 (runner exits 0 with a warning) and R4 (hook not invoked at `applied=0`).
2. Edit the post-apply block; run → 8 passed. `bash scripts/lint-orphan-test-suites.sh` → clean (no new file).
3. `bash plugins/soleur/test/fixture-relative-assert.test.sh`; if any row moved, `--write-baseline` in the same commit and name the changed operand in the commit message.
4. `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` → exit 0 after refreshing the `run-migrations.sh` allowlist reason and adding the regex comment.

### Phase 3 — Live retirement (pipeline-performed; roots first, every config verified)

Run from the worktree once the code no longer references `SUPABASE_PAT`. Values never reach argv or stdout; every probe is errexit-safe and reports `probe-failed(...)` instead of aborting silently (Kieran); a positive control on the built-in `DOPPLER_CONFIG` secret distinguishes "absent" from "Doppler unreachable"; an empty token cannot masquerade as a 401; each config independently gated (`hr-bulk-delete-per-item-live-infra-role-check`):

```bash
set -euo pipefail
case "$-" in *x*) echo "refusing under xtrace" >&2; exit 78 ;; esac
has() { doppler secrets get "$2" -p soleur -c "$1" --plain >/dev/null 2>&1; }        # rc 1 when absent OR unreachable
ctl() { has "$1" DOPPLER_CONFIG || { echo "$1: doppler unreachable (positive control failed)"; exit 1; }; }
probe() {  # $1=config $2=name → HTTP code of GET /v1/projects with that token, or probe-failed(...); token never in argv
  local c
  c="$(doppler secrets get "$2" -p soleur -c "$1" --plain \
        | { IFS= read -r t && [[ -n "$t" ]] && printf 'Authorization: Bearer %s' "$t"; } \
        | curl --disable --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 30 --header @- https://api.supabase.com/v1/projects)" \
    || { printf 'probe-failed(rc=%s,http=%s)' "$?" "$c"; return 0; }
  printf '%s' "$c"
}
retire() {
  local cfg="$1" code rc=0
  ctl "$cfg"
  has "$cfg" SUPABASE_PAT || { echo "$cfg: SUPABASE_PAT already absent"; return 0; }
  code="$(probe "$cfg" SUPABASE_PAT)"
  [[ "$code" == "401" || "$code" == "403" ]] || { echo "$cfg: SUPABASE_PAT probe=$code — not proven dead, refusing to delete (re-run the loop if probe-failed)"; exit 1; }
  [[ "$cfg" == prd ]] && { has prd SUPABASE_ACCESS_TOKEN || { echo "prd: SUPABASE_ACCESS_TOKEN absent — refusing"; exit 1; }; }
  doppler secrets delete SUPABASE_PAT -p soleur -c "$cfg" --yes >/dev/null || rc=$?   # stdout dumps the whole config (learning 2026-05-26)
  echo "$cfg: doppler secrets delete rc=$rc"; [[ "$rc" -eq 0 ]] || exit 1
  has "$cfg" SUPABASE_PAT && { echo "$cfg: SUPABASE_PAT still present after delete"; exit 1; }
  echo "$cfg: SUPABASE_PAT deleted, verified absent"
}
for cfg in dev prd; do retire "$cfg"; done                                                                       # roots
for cfg in dev_personal dev_scheduled prd_cla prd_ghcr prd_kb_drift_walker prd_scheduled prd_terraform prd_workspaces_luks; do retire "$cfg"; done   # branches: expected "already absent"; a still-present name is an override and is deleted
for cfg in ci cli cli_ops; do ctl "$cfg"; has "$cfg" SUPABASE_PAT && { echo "$cfg: unexpected SUPABASE_PAT"; exit 1; } || echo "$cfg: absent (never carried it)"; done
```

Record all thirteen per-config lines (two `deleted, verified absent`, eight expected `already absent` — or `deleted` for an override — and three `absent`) plus the two `doppler secrets delete rc=` lines in the PR body. The prd root is live production configuration; the write is a deletion of a credential the vendor already rejects, scoped by name, gated per item, with no replacement value written anywhere.

### Phase 4 — Documentation sweep

Edit `migration-rollback.md`, the credential-rotation runbook, `secret-scanning.md`, and the 2026-05-21 learning per Files to Edit. Then the residual check: `git grep -n SUPABASE_PAT -- . ':!*.json' ':!knowledge-base/project/plans/' ':!knowledge-base/project/specs/' ':!**/archive/**' ':!knowledge-base/project/learnings/' ':!knowledge-base/engineering/architecture/decisions/' ':!knowledge-base/support/' ':!plugins/soleur/skills/work/SKILL.md'` returns only `scripts/lint-supabase-deprecated-endpoints.sh` (detector regex + header/allowlist prose), `scripts/lib/scrub-supabase-pat.sh` (file name / header prose), `scripts/rotate-supabase-db-credential.sh` (past-tense comment). Every remaining hit is a detector, a library name, or a historical record — not a consumer.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure surfaces are Soleur's own CI: a red `migrate` job that blocks a prd release (old code keeps serving against a backward-compatible schema). The user-facing artifact this plan *removes* is `PGRST205` errors on features that read a freshly-migrated table during the up-to-ten-minute window after a deploy.
- **If this leaks, the user's data is exposed via:** the account-scoped Supabase Management-API token, which reaches every project's database. This plan shrinks that exposure: the token leaves curl argv, gains an xtrace refusal, gains proxy/curlrc confinement, its dead twin is deleted from ten configs, and — after plan review — it is handed to no `pull_request`-triggered job and copied into no new config.
- **Brand-survival threshold:** `aggregate pattern` — the harm class is repeated transient degradation after migrations (every release, all users, ≤10 min), not a per-user breach; the credential surface is net-reduced.

## Observability

```yaml
liveness_signal:
  what: "The migrate job's exit status and annotations: the reload hook now runs on every migration run; 'postgrest-reload-schema: reload acknowledged (ref=…, HTTP 2xx)' on success; a rejected credential prints '::error::postgrest-reload-schema: Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP 401|403)…' and, when the run applied a migration, fails the job with '::error title=Supabase rejected the migration credential::'; on a no-op run it prints '::warning title=Schema-cache refresh refused on a no-op run::'."
  cadence: "per migration run — every prd release (web-platform-release.yml migrate job), every push/PR run of tenant-integration.yml (dev: token absent by design → '::warning::… not set' every run), every rls-authz-fuzz.yml run (local stack: same absence warning)"
  alert_target: "prd: release-outcome classifies a failed migrate as non-delivery and emails ops@ via Resend (a Sentry event fires only if that email is not delivered); no Slack arm fires for a migrate failure. Dev CI: none by design (no credential) — the warning is informational."
  configured_in: ".github/workflows/web-platform-release.yml (migrate, release-outcome), apps/web-platform/scripts/run-migrations.sh (post-apply block), apps/web-platform/scripts/postgrest-reload-schema.sh (401|403 arm)"

error_reporting:
  destination: "GitHub Actions annotations from the script (stderr '::error::…' with the scrubbed API response body and the Doppler config name) and from the runner (titled '::error'/'::warning'); prd non-delivery reaches ops@ by Resend email from release-outcome, with Sentry (NEXT_PUBLIC_SENTRY_DSN) as the fallback when the email is undelivered"
  fail_loud: "job exit code equals the hook's exit code (2) whenever a migration was applied and the credential was rejected; the annotation names SUPABASE_ACCESS_TOKEN, the Doppler config, and the resolved project ref"

failure_modes:
  - mode: "SUPABASE_ACCESS_TOKEN rotated/expired at the vendor (Management API 401/403 with a JSON body)"
    detection: "hook exits 2 under --best-effort; a migrate run that applied something goes red with '::error title=Supabase rejected the migration credential::'; a no-op run prints the titled '::warning' (so the dead token is visible on the very next release, migration or not)"
    alert_route: "prd: release-outcome → Resend email to ops@ (Sentry fallback); nothing pages on the no-op warning by design — the next migration-carrying release does"
  - mode: "Edge/WAF 401/403 without an API body, curl network failure, 5xx, HTTP 000"
    detection: "hook exits 0 under --best-effort with '::warning::postgrest-reload-schema: … (best-effort: skipping)'; strict mode exits 1; PostgREST's natural ~10-min poll is the fallback"
    alert_route: "warning annotation only (by design — a retry-able class must not block a release); the next run retries because the hook runs on every run"
  - mode: "Wrong project ref / project not visible to the token (HTTP 404)"
    detection: "unchanged from main: exit 2 strict, soaked under --best-effort with the resolved ref echoed on stderr before the POST and the response body in the warning"
    alert_route: "warning annotation; ref drift also breaks the app itself, which has its own alerting"
  - mode: "Doppler retirement loop refuses (a SUPABASE_PAT probe not 401/403, probe-failed, positive control failed, delete rc≠0, or still present after delete)"
    detection: "the Phase 3 loop exits 1 naming the config and the reason before or immediately after the offending step"
    alert_route: "work-phase output; the PR does not reach ready until the loop's thirteen lines are recorded"

logs:
  where: "GitHub Actions run logs for web-platform-release.yml (migrate) and tenant-integration.yml (Apply migrations to dev); token values never appear (stdin header + scrub_pat; no token in any PR job)"
  retention: "GitHub Actions default log retention (90 days)"

discoverability_test:
  command: "bash apps/web-platform/scripts/postgrest-reload-schema.test.sh"
  expected_output: "Results: 18 passed, 0 failed"
```

## Guard Contract

### Guard 1 — rejected credential fails a migration run that applied something

**Property.** Whenever `run-migrations.sh` applies at least one migration and the Management API answers the reload POST with 401 or 403 carrying a JSON body, the migration run exits non-zero with a titled `::error` annotation — under `--best-effort` as well as strict mode; and on a run that applied nothing the same rejection produces a titled `::warning` without failing the run.

**Assembly.** Chokepoint one: `postgrest-reload-schema.sh`'s HTTP-status `case` (arms `2??`, `401|403`, `4??`, `5??`, `*`) — every response passes through exactly this switch; the property quantifies over the `401|403` arm and its JSON-body branch. Chokepoint two: the single call site in `run-migrations.sh`'s post-apply block (`bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`, now unconditional, followed by the `applied > 0` branch) — the only place the hook is invoked from a migration run; its exit code must reach the runner's `exit`. The three workflow callers (`web-platform-release.yml` migrate, `tenant-integration.yml` apply, `rls-authz-fuzz.yml` local) all reach the hook through that one call site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In the script, change the `401\|403)` JSON-body branch back to `fail_or_skip 2 …` | RED — T15, T15b (401/403 + JSON under `--best-effort` must exit 2) |
| 2 | In the script, make the `401\|403)` arm honour `best_effort` (exit 0 + warning) — the guard's own dispatch | RED — T15, T15b |
| 3 | In the script, drop the JSON-body discrimination (treat every 401/403 as hard) | RED — T15c (HTML-body 403 under `--best-effort` must exit 0; strict must exit 1) |
| 4 | Add a second arm `403)` above `401\|403)` that calls `fail_or_skip` (a second member after a compliant first) | RED — T15b |
| 5 | In `run-migrations.sh`, restore `if ! bash …; then echo "::warning …"; fi` (swallow the hook's exit) | RED — R2 |
| 6 | In `run-migrations.sh`, fail the run regardless of `applied` | RED — R4 (`applied=0` + hook rc 2 must exit 0 with the titled warning) |
| 7 | In `run-migrations.sh`, restore `if [[ "$applied" -gt 0 ]]` around the hook call | RED — R4 (`hook-ran` marker must exist at `applied=0`) |

**Harness rows.**

- Suite mutation that must RED: in the test's fake curl, stop rendering `$CURL_HTTP_CODE` (print only the body) — T5 and T12 (which assert `rc == 2` on 401/404) and T15/T15b fail because the empty code falls to the catch-all (exit 1).
- Suite mutation that must RED: in `run-migrations-schema-probe.test.sh`, make the stub hook ignore `FAKE_RELOAD_HOOK_RC` and always `exit 0` — R2 and R4 fail.
- Must-PASS non-canonical inputs the contract explicitly permits: HTTP 503 under `--best-effort` exits 0 (T8); token unset under `--best-effort` exits 0 (T2); HTML-body 403 under `--best-effort` exits 0 (T15c); `applied=0` with a failing hook exits 0 (R4).

## Infrastructure (IaC)

Phase 2.8 reviewed. This plan introduces **no** new infrastructure: no server, service, secret, DNS record, vendor account, or firewall rule. The only live-infrastructure write is the **deletion** of a dead, name-scoped Doppler secret that Terraform has never managed (`git grep 'resource "doppler_secret"' -- 'apps/web-platform/infra/*.tf'` names no `SUPABASE_*`), so there is no `.tf` resource to remove and importing a dead credential into state solely to destroy it would add a Terraform-held copy of a secret for no benefit. The one Terraform-managed artifact in this credential family — `github_actions_secret.supabase_access_token` (`apps/web-platform/infra/inngest.tf`, value from `var.supabase_access_token` in Doppler `prd_terraform`) — is untouched, and after plan review no workflow change consumes it.

### Terraform changes

None. No providers, variables, or resources change.

### Apply path

Not applicable (no Terraform change). The Doppler deletion runs in the work phase via the CLI loop in Implementation Phase 3, gated per config on a live 401/403 probe with a Doppler positive control.

### Distinctness / drift safeguards

`dev != prd` is preserved and strengthened: after this plan no account-scoped Supabase token exists in any `dev`-environment config, and none is reachable from a `pull_request` job. No `lifecycle.ignore_changes` is involved. No secret value lands in `terraform.tfstate` as a result of this plan.

### Vendor-tier reality check

Not applicable — no resource creation.

## Open Code-Review Overlap

- #3364 — "review: add postgres-role ownership guard to run-migrations.sh (PR #3355 follow-up)". **Acknowledge:** it concerns the apply phase's role ownership, a different block of `run-migrations.sh`; this plan edits only the post-apply reload hook block. The scope-out remains open.

## Domain Review

**Domains relevant:** engineering, operations

### Engineering

**Status:** reviewed
**Assessment:** (A) Blocking the prd deploy on a rejected credential is the correct blast radius: failure lands after apply, old code keeps running on a backward-compatible schema, `release-outcome` reports the non-delivery; the alternative trades that for ~10 min of `PGRST205` 500s for real users with no rollback lever. `verify-migrations` is skipped on a red `migrate` (acceptable). (B) Consumers beyond script/test: `run-migrations.sh` comment, `rotate-supabase-db-credential.sh` comment (already correct), the deprecated-endpoints allowlist reason text; both shell-trace baselines list the script and become false statements once it is clean — regenerate in the same PR; the test file needs a case for 401-under-best-effort=2. (C) The CTO's recommendation to harden all non-429 4xx was **not adopted** after plan review (both the simplification and correctness panels fired on that scope; P2 names 401/403). (D) Fork PRs already fail on the Doppler-token check; the step-level env injection the CTO reviewed was subsequently **removed** on the architecture-strategist's `pull_request`-exposure finding. (E) No ADR: credential retirement plus failure-semantics tightening in one script; no new boundary.

### Operations

**Status:** reviewed
**Assessment:** Zero cost delta; `knowledge-base/operations/expenses.md` lists Supabase Pro + domain and the Inngest Micro project with no token rows — no ledger edit. Vendor-side revocation: the token is already dead at Supabase (401 everywhere); no public Management-API endpoint for PAT list/revoke is known, and the repo's own rotation runbook routes revocation through the dashboard — do not add a vendor step; state "already 401 at vendor" in the PR. Process: `secret-scanning.md` `### SUPABASE_ACCESS_TOKEN` is stale for the post-change topology; amend with the inherited-from-`prd`-root fan-out, the TF-published GH secret, and the blast-radius statement. Folded into Files to Edit.

**Brainstorm-recommended specialists:** none (no brainstorm).

## Plan Review Record

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto (devex lens); advisor consult (opus). Mechanical findings applied in this revision are summarised in the Overview. Taste / User-Challenge items routed to `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`: DC-1 (dev token sourcing declines both operator-offered arms — User-Challenge), DC-2 (DHH: relocate the soft-fail policy from the script's `--best-effort` flag into the caller — Taste, not applied), DC-3 (spec-flow/architecture: add a retry before classifying a non-2xx — Taste, not applied), DC-4 (DHH: drop the runbook/secret-scanning/learning doc edits from the critical path — Taste, not applied; COO asked for the runbook line).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` prints `Results: 18 passed, 0 failed` (15 existing + T15, T15b, T15c). This covers: dead-but-present token is loud (T15/T15b: 401/403 + JSON body under `--best-effort` → exit 2, stderr has `::error::` and `Supabase rejected SUPABASE_ACCESS_TOKEN`, no `skipping`); absence and transience stay soft (T2, T8, T15c); bearer on stdin, absent from argv (T4); `--help` carries the `prd_terraform` one-liner (T9).
- [ ] AC2 — `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` prints `Results: 8 passed, 0 failed` (5 existing + R1, R2, R4).
- [ ] AC3 — `git grep -c 'SUPABASE_PAT' -- apps/web-platform/scripts/postgrest-reload-schema.sh apps/web-platform/scripts/postgrest-reload-schema.test.sh apps/web-platform/scripts/run-migrations.sh apps/web-platform/scripts/run-migrations-schema-probe.test.sh` reports no matches for any of the four, and `git grep -c 'SUPABASE_ACCESS_TOKEN' -- apps/web-platform/scripts/postgrest-reload-schema.sh` ≥ 5.
- [ ] AC4 — `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 (the CI invocation) and `python3 scripts/lint-shell-trace-credential-refusal.py` (full tree) exits 0; `grep -c 'postgrest-reload-schema.sh' scripts/lint-shell-trace-credential-refusal.baseline.txt scripts/lint-shell-trace-credential-refusal-d.baseline.txt` reports 0 for each; `git diff --numstat origin/main -- scripts/lint-shell-trace-credential-refusal.baseline.txt scripts/lint-shell-trace-credential-refusal-d.baseline.txt` shows `0 1` for each (one removed line, nothing added).
- [ ] AC5 — `grep -c "| curl --disable --noproxy '\*'" apps/web-platform/scripts/postgrest-reload-schema.sh` = 1; `grep -c -- '--header @-' apps/web-platform/scripts/postgrest-reload-schema.sh` = 1; `grep -c 'Authorization: Bearer \${SUPABASE' apps/web-platform/scripts/postgrest-reload-schema.sh` = 0.
- [ ] AC6 — `awk '/# Post-apply: force a PostgREST/{f=1} f' apps/web-platform/scripts/run-migrations.sh` contains `|| hook_rc=$?`, `exit "$hook_rc"`, `::error title=Supabase rejected the migration credential::` and `::warning title=Schema-cache refresh refused on a no-op run::`; `grep -c 'if \[\[ "\$applied" -gt 0 \]\]; then' apps/web-platform/scripts/run-migrations.sh` = 0 (the hook is unconditional); `grep -c 'any non-zero exit it returns is itself a bug' apps/web-platform/scripts/run-migrations.sh` = 0.
- [ ] AC7 — `bash scripts/lint-orphan-test-suites.sh` exits 0 and `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0 (baseline regenerated in the same commit if any row moved, with the changed operand named in the commit message).
- [ ] AC8 — `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` exits 0; `grep -c 'intentionally retained after #8028' scripts/lint-supabase-deprecated-endpoints.sh` = 1.
- [ ] AC9 — `git diff --stat origin/main -- .github/workflows/` is empty (no workflow change; in particular no `secrets.SUPABASE_ACCESS_TOKEN` reaches `tenant-integration.yml`): `grep -c 'SUPABASE_ACCESS_TOKEN' .github/workflows/tenant-integration.yml` = 0.
- [ ] AC10 — Phase 1 step 5 evidence in the PR body: the strict-mode dev run printed `reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2` (prefix; 200 or 201).
- [ ] AC11 — All thirteen Doppler configs verified, recorded in the PR body as the Phase 3 loop's per-config lines; reviewer re-verification (positive control first, so "unreachable" cannot read as "absent"): `for c in dev dev_personal dev_scheduled ci prd prd_cla prd_ghcr prd_kb_drift_walker prd_scheduled prd_terraform prd_workspaces_luks cli cli_ops; do doppler secrets get DOPPLER_CONFIG -p soleur -c $c --plain >/dev/null 2>&1 || { echo "$c: UNREACHABLE"; continue; }; doppler secrets get SUPABASE_PAT -p soleur -c $c --plain >/dev/null 2>&1 && echo "$c: STILL PRESENT" || echo "$c: absent"; done` prints thirteen `absent` lines and no `UNREACHABLE`.
- [ ] AC12 — Same shape with `SUPABASE_ACCESS_TOKEN`: `present` for `prd` and its six branches, `absent` for `dev`, `dev_personal`, `dev_scheduled`, `ci`, `cli`, `cli_ops`; `gh secret list | grep -c '^SUPABASE_ACCESS_TOKEN'` = 1 (P5: no new copy).
- [ ] AC13 — Residual sweep: the Phase 4 `git grep` (with its pathspec exclusions) lists no file other than `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/lib/scrub-supabase-pat.sh`, `scripts/rotate-supabase-db-credential.sh`.
- [ ] AC14 — `grep -c 'SUPABASE_PAT' apps/web-platform/docs/migration-rollback.md` = 0 and `grep -c 'prd_terraform' apps/web-platform/docs/migration-rollback.md` ≥ 1; `grep -c 'Updated 2026-09-13 — #8028' knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` = 1; `grep -c 'retired in #8028' knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` = 1.
- [ ] AC15 — `bash scripts/test-all.sh` green at the `/ship` Phase 4 full-battery checkpoint (no TypeScript touched).
- [ ] AC16 — PR body uses `Closes #8028` (code, docs, and the Doppler deletion all land pre-merge), states "SUPABASE_PAT was already 401 at the vendor; no dashboard revocation step exists or is needed", and carries the `## Model Dissents (informational)` block that `/ship` renders from `decision-challenges.md`.

### Post-merge (operator)

None. The Doppler deletion is performed in the work phase by the pipeline (Implementation Phase 3); the first prd release exercises the new path with the `prd` root's `SUPABASE_ACCESS_TOKEN` and needs no operator action.

## Test Scenarios

- Script, strict mode: token unset → 2 with the Doppler-config-naming message (T1); URL unset → non-zero (T3); malformed URL → non-zero (T7); 200 → 0 with endpoint + NOTIFY body in argv, bearer on stdin, bearer absent from argv (T4); 401 + JSON → 2 (T5); 503 → 1 (T6); 404 → 2 (T12); 000 → 1 (T13); custom-domain CNAME → correct ref (T13b); `SUPABASE_API_HOST` ignored (T14); curl rc 6 → 1 and token scrubbed (T11); `--help` → 0 mentioning `SUPABASE_ACCESS_TOKEN` and `-c prd_terraform --plain` (T9); unknown flag → 2 (T10); 403 + HTML → 1 (T15c strict half).
- Script, `--best-effort`: token unset → 0 + warn (T2); 503 → 0 + warn (T8); 403 + HTML → 0 + warn (T15c); **401 + JSON → 2 + `::error::`, no `skipping` (T15)**; **403 + JSON → 2 (T15b)**.
- Runner (schema-probe harness): applied, hook 0 → 0, `hook-ran` present (R1); applied, hook 2 → 2 + titled `::error` (R2); nothing applied, hook 2 → 0 + titled `::warning`, `hook-ran` present (R4); the five existing probe cases unchanged with the stub hook planted.
- Live: Phase 1 step 5 dev reload acknowledged; Phase 3 loop output (thirteen lines + two delete rc lines); Phase 0 re-probe of both tokens.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Mint a new `SUPABASE_PAT` | Restores a redundant second account-level token; the issue's own recommendation is to retire it. |
| Copy the prd `SUPABASE_ACCESS_TOKEN` into Doppler `dev`/`dev_scheduled` (operator-offered arm) | `dev_scheduled` is consumed by a `pull_request` job: PR-authored SQL/shell would hold a credential that can run arbitrary SQL on prd (`hr-dev-prd-distinct-supabase-projects`). |
| Inject `secrets.SUPABASE_ACCESS_TOKEN` as step env in `tenant-integration.yml` (plan v1) | Same exposure — the job runs on `pull_request`; every existing consumer of that secret is `push`/`schedule`/`workflow_dispatch`-only. Removed at plan review (architecture P0). |
| Fail dev CI loudly on the absent token | Reds every migration-carrying PR forever for a credential CI must not hold; "fail loudly" in the issue is about a *present* dead token. |
| Keep the job green and mirror the rejection to Sentry from bash | Deploying over a stale schema cache produces `PGRST205` for real users for up to ten minutes; a delayed release is strictly safer, and `release-outcome` already reports a red `migrate`. |
| Harden all non-429 4xx (CTO), with a 429 carve-out (plan v1) | 404/422 have not been observed, are soaked on main today, and are not in the property list; the expansion dragged in three tests and a second helper caller. Cut at plan review (simplicity P1). |
| Move the soft-fail policy into `run-migrations.sh` and delete `--best-effort` (DHH) | Deletes a documented flag and rewrites T2/T8 for the same P2 outcome; the narrower change (one hard arm) is the smaller diff. Recorded as DC-2. |
| Retry once before classifying a non-2xx (spec-flow / architecture) | The hook now runs on every migration run, so a transient 403 costs one job re-run that reloads; a retry loop inside a 15-second best-effort hook is machinery for a case the JSON-body discrimination already narrows. Recorded as DC-3. |
| Run the reload hook as its own workflow step | The runner's titled annotation plus propagated exit code already attributes the failure. |
| Migrate the inline `scrub_pat` to `scripts/lib/scrub-supabase-pat.sh` | The lib's header explicitly defers migrating pre-existing copies to a separate sweep. |
| Delete the Doppler secrets via Terraform | Neither secret is Terraform-managed; importing a dead credential into state to destroy it adds a state-held copy for nothing. |
| Vendor-side revocation via Playwright | The token already returns 401 at the vendor — there is nothing to revoke that changes any behaviour. |

## Dependencies & Risks

- **Risk: a future `SUPABASE_ACCESS_TOKEN` expiry now blocks prd releases that apply a migration.** Intended (that is the loud failure), and visible one release earlier as a titled warning on no-op runs. Mitigation: `secret-scanning.md` rotation section names the inherited fan-out and the blast radius; the fix is one rotation (Doppler `prd` root + `terraform apply` for the GH secret) and a job re-run, which now reloads.
- **Risk: dev CI keeps skipping the reload.** Accepted and recorded (DC-1): PR-triggered jobs must not hold a prd-reaching credential; PGRST205 flakes in dev remain bounded by the ~10-min poll, exactly as since the PAT died.
- **Risk: the schema-probe suite goes red because the relocated runner has no hook file.** Addressed in Phase 2 step 1 (stub hook planted in `make_temp_tree`) before the runner change lands.
- **Risk: fixture-relative-assert baseline row moves.** AC7 regenerates in the same commit with the operand named.
- **Risk: `--header @-` on an old curl.** Phase 0 checks `curl --version` ≥ 7.55; CI runners ship 8.x; the production precedent already relies on it.
- **Risk: the Phase 3 loop refuses on a config.** It exits before any delete (or immediately after a failed one), naming the config and reason; `probe-failed(...)` means re-run the loop, not skip the config. The PR is not marked ready until the thirteen lines are recorded.
- **Dependency:** `doppler` CLI authenticated for project `soleur` with write access to the `dev` and `prd` roots (read probes succeeded in this session; the delete is the first write and surfaces a permission error, captured as `rc≠0`, before any state changes).

## References & Research

- Issue #8028; PRs #4286, #4320, #7793; issues #4285, #7797, #7873, #7966, #3364.
- `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` §1, §Prevention 3.
- `knowledge-base/project/learnings/security-issues/2026-05-26-doppler-secrets-delete-dumps-full-config-to-stdout.md`.
- `knowledge-base/project/learnings/2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md`.
- `knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md`; `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.
- `knowledge-base/project/learnings/2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`.
- `knowledge-base/project/learnings/2026-05-16-repo-research-must-inventory-scheduled-ci-workflows-for-secret-sweeps.md`.
- `knowledge-base/project/learnings/best-practices/2026-04-22-plan-ac-external-state-must-be-api-verified.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-197-a-zero-from-a-log-surface-is-not-evidence-of-absence.md`; `knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md`.
- `scripts/supabase-logs-query.sh` (`api_get`: the `curl --disable --noproxy '*' --header @-` model); `scripts/rotate-supabase-db-credential.sh` (`TOKEN_CONFIG=prd_terraform` precedent; xtrace preamble precedent); `apps/web-platform/scripts/seed-dev-users.sh` (`DOPPLER_CONFIG` precedent).
- Supabase Management API: `GET /v1/projects` and `GET /v1/projects/{ref}` (liveness/visibility probes), `POST /v1/projects/{ref}/database/query` (the reload). All exercised live during planning.
