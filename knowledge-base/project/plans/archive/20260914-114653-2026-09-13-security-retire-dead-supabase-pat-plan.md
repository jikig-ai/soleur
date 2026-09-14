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

## Enhancement Summary

**Deepened on:** 2026-09-13 (v3)
**Sections enhanced:** Proposed Solution, Technical Considerations, Files to Edit, Implementation Phases, Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Research Insights
**Research agents used:** framework-docs-researcher (Supabase Management API error shape), verify-the-negative sweep (9 claims, all confirmed), security-sentinel, silent-failure-hunter, test-design-reviewer, observability-coverage-reviewer, git-history-analyzer (citation verification), learnings-researcher (narrow topics)

### Key Improvements

1. **One soak rule instead of an inline exception.** Under `--best-effort` the script soaks a failure only when the token is **unset** (never opted in → `::notice::`) or the failure is **transient** (exit-1 class → `::warning::`); everything else with a token present — a JSON-bodied 401/403, a 404, an unset/unparseable URL, a missing `curl` — exits 2. Implemented as one condition inside the existing `fail_or_skip`; v2's inline `401|403` arm and its second helper disappear (silent-failure-hunter P1 + code-simplicity).
2. **A rejected credential fails the migration run regardless of `applied`.** v2 downgraded it to a warning on no-op runs; since most prd releases apply nothing, that reproduced the "warning nobody reads" class #8028 opened on (silent-failure-hunter P1). The hook still runs on every run (so a re-run after rotation reloads), and any non-zero hook exit now fails the run, with the title keyed on `rc == 2`.
3. **Measured, not asserted:** the dead token's real 401 body is `{"message":"Unauthorized"}` (26 bytes, `Content-Type: application/json`) on both `GET /v1/projects` and `POST /v1/projects/mlwiodleouzwniehynfz/database/query` (security-sentinel P1: the discrimination premise had only been fixtured). Leading whitespace is tolerated (`=~ ^[[:space:]]*\{`). A post-retirement live negative control (malformed `sbp_` value against dev under `--best-effort` → exit 2) is an AC.
4. **prd absence is no longer silent:** `SUPABASE_ACCESS_TOKEN` joins `apps/web-platform/scripts/verify-required-secrets.sh`, so a token missing from the `prd` root reds `verify-doppler-secrets` before deploy and `release-outcome` emails it (observability-coverage-reviewer P1).
5. **Phase 3 loop hardened:** one Doppler listing per config (no TOCTOU between reachability and presence), 401 + `{`-prefixed body as the "proven dead" gate (a WAF 403 can no longer prove anything), a sha256 hash pin against the `dev` root's value so a branch-level override with a *different* value is refused, and the loop runs as a file, not pasted.
6. **Harness fixes the test-design reviewer would otherwise have caught at GREEN time:** T3 hand-builds its tree outside `make_temp_tree`, so a `plant_reload_stub` helper is called from both; the stub heredoc must be quoted (`<<'STUB'`) — an unquoted one would `touch` a file in the live repo at plant time and freeze the rc; fake env goes on the `env -i` lines; vacuity floor 5 → 8.
7. **Citation corrected:** the xtrace-refusal lint landed in PR #7858 (2026-09-06), not #7793 (a DNS PR).

### New Considerations Discovered

- Every consumer of `secrets.SUPABASE_ACCESS_TOKEN` is `push`/`schedule`/`workflow_dispatch`-only; `tenant-integration.yml` references only `DOPPLER_TOKEN_DEV_SCHEDULED` — but `dev_scheduled` carries other account-scoped credentials (Stripe, Cloudflare audit, Discord, X, Buttondown, the GitHub App key) that are outside #8028's scope; the attack-surface row is narrowed to the Supabase Management-API credential.
- `release-outcome` reports a failed `migrate` by Resend email to ops@ with Sentry only as the undelivered-email fallback; `notify-gated` never fires for it — the Observability section states exactly that.
- `scrub_pat` now also strips CR/LF/FF/VT/ESC/DEL and caps the body at 512 bytes before it reaches a `::error::` line (a body line beginning with `::` would otherwise be parsed as a runner command).

# security: retire the dead `SUPABASE_PAT`, migrate the PostgREST reload to `SUPABASE_ACCESS_TOKEN`, fail loudly on a rejected credential

## Overview

The PostgREST schema-reload script authenticates to the Supabase Management API with a personal access token that every Doppler config now rejects. Because the migration runner invokes the script in its soft-fail mode, the rejection is reported as a warning and the reload never happens; nothing pages. This plan moves the script onto the one Management-API token that still works, makes a rejected credential a hard failure of a migration run that applied something, retires the dead token from every config that inherits it, and sweeps the remaining repo references so the retired name has no surviving consumer.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec file exists under `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/` on this branch.

**Plan-review revision (v2, 2026-09-13; superseded in part by the v3 deepen pass — see Enhancement Summary above for what changed again).** Six reviewers (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO-devex) plus a scoped advisor consult. Applied: hardening narrowed to `401|403` only (the `404`/`422`/`429` expansion and its tests cut); runner tests folded into the existing schema-probe harness (no new test file); lint-duplicating tests cut; the hook now runs on **every** migration run so a re-run after a credential fix actually reloads; `401|403` with a non-JSON body classified transient (an edge/WAF 403 must not block a release); Phase 3 loop made errexit-safe with a Doppler positive control and an empty-token guard; observability channels corrected (Resend email, not Sentry/Slack); operator-facing error text; enumerated-config prose replaced by "prd root (inherited)". **Removed on a security finding:** the `tenant-integration.yml` token injection — that workflow runs on `pull_request`, so an account-scoped, prd-reaching credential would be handed to PR-authored code (`hr-dev-prd-distinct-supabase-projects`); the same holds for copying the value into Doppler `dev`/`dev_scheduled`. Dev CI therefore keeps the script's absence-soak (a `::notice::`), which is a User-Challenge to the two arms the operator offered and is recorded in `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`.

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

  Both tokens are `sbp_`-prefixed, 44 chars — the existing `scrub_pat` regex (`sbp_[A-Za-z0-9]{20,}`) covers the replacement token unchanged. The GitHub Actions repo secret `SUPABASE_ACCESS_TOKEN` exists (`gh secret list`, updated 2026-06-18), written by `github_actions_secret.supabase_access_token` in `apps/web-platform/infra/inngest.tf` from the `supabase_access_token` Terraform variable (Doppler `prd_terraform`, `TF_VAR_supabase_access_token`). Neither token is a Terraform-managed `doppler_secret` (`git grep 'resource "doppler_secret"' -- 'apps/web-platform/infra/*.tf'` names no `SUPABASE_*`), so a CLI delete creates no drift.
- **Doppler topology** (`doppler configs -p soleur --json`): roots are `dev`, `ci`, `prd`, `cli`; the others are branch configs (`root=false`). `doppler secrets get <missing> --plain` exits **1** — and so does a missing/unreadable config or a revoked CLI token (Kieran, verified). `doppler secrets --only-names --json -p soleur -c <cfg>` returns one JSON object keyed by secret name (verified on `ci`: 25 keys incl. the built-ins `DOPPLER_CONFIG`/`DOPPLER_ENVIRONMENT`/`DOPPLER_PROJECT`), so a single listing yields both reachability and presence without a second call. Learning `knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`: branch configs inherit the entire root set; delete at the root to remove from every branch.
- **The dead token's real rejection body, measured 2026-09-13 (bearer on stdin, body to a scratch file):** `GET /v1/projects` → `http=401`, `Content-Type: application/json; charset=utf-8`, body `{"message":"Unauthorized"}` (26 bytes, first byte `{`); `POST /v1/projects/mlwiodleouzwniehynfz/database/query` with the NOTIFY payload → identical `401` + `{"message":"Unauthorized"}`. The repo's `apply-inngest-rls.yml` recorded the same body shape on 2026-07-15, and learning `2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md` records a validation-class 401 as `{"message":"Custom SMTP required …"}` — every observed Management-API 401 is a `{`-prefixed JSON object.
- **Live token reaches every project ref the script can resolve** (read-only, `prd_terraform` value, bearer on stdin): `GET /v1/projects/{ref}` → 200 for `mlwiodleouzwniehynfz` (dev; `NEXT_PUBLIC_SUPABASE_URL` in `dev` is `https://mlwiodleouzwniehynfz.supabase.co`), `ifsccnjhymdmidffkzhl` (prd web-platform; `prd` URL is the custom domain `https://api.soleur.ai`, resolved by the script's CNAME fallback), `pigsfuxruiopinouvjwy` (prd inngest).
- **The GH Actions secret value is live**: `scheduled-supabase-advisor-scan.yml`, which authenticates with `${{ secrets.SUPABASE_ACCESS_TOKEN }}`, concluded `success` on 2026-09-11, -12 and -13 (`gh run list`). Recorded for completeness — this plan no longer routes any job through that secret.
- **`doppler run` ambient-env passthrough** verified (`FOO_PROBE_8028=yes doppler run -p soleur -c dev -- printenv FOO_PROBE_8028` → `yes`): the local-operator invocation below relies on it.
- **`doppler secrets delete` CLI form** verified via `--help`: `doppler secrets delete [secrets] -p <project> -c <config> --yes` (`-y, --yes  proceed without confirmation`).
- **ADR corpus grep** for the proposed mechanisms (`best-effort`, `soft-fail`, `account-scoped`, `SUPABASE_ACCESS_TOKEN`): no ADR rejects hardening a soft-fail branch or names token placement. ADR-197 records that `scripts/lint-supabase-deprecated-endpoints.sh`'s host-pin arm is keyed on files matching `/v1/projects|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`; ADR-216 cites "a dead `SUPABASE_PAT`" as an example of a live incident that reads like machinery. Neither constrains the design beyond "make it observable".

### Property List and Cut List (Phase 0.6b)

**Properties (observable outcomes the ask is for):**

- P1 — After a migration apply in prd (and when an operator runs the script by hand), the PostgREST schema reload is actually acknowledged by the Management API (HTTP 2xx), because the script authenticates with a credential the API accepts.
- P2 — A credential the Management API rejects (401/403 with an API response body) produces a non-zero script exit and a job-visible failure of the migration run — on every run, applied or not — never a soft skip, regardless of `--best-effort`.
- P3 — An environment that never opted in (no token / no project URL — the local Supabase stack in `rls-authz-fuzz.yml`, and dev CI, which must not hold a prd-reaching credential) still does not fail its migration run under `--best-effort`; transient upstream failure is still soaked.
- P4 — No Doppler config carries `SUPABASE_PAT` afterwards, and no tracked file names it as a consumer (historical mentions in learnings/ADRs/archives may remain).
- P5 — The account-scoped Management-API token is not copied into any additional Doppler config or `pull_request`-triggered job; the credential surface shrinks (10 configs carrying a dead account-scoped token → 0; the live one stays in the `prd` root + its inherited branches + the one GH secret).
- P6 — The fail-loud behaviour is verifiable locally (shell test suites) and in CI without SSH.

**Mechanisms → property → coverage on `origin/main`:**

| Mechanism | Buys | Already covered? | Disposition |
|---|---|---|---|
| Rename script/test/header env var to `SUPABASE_ACCESS_TOKEN` | P1, P4 | No | Keep |
| Under `--best-effort`, soak only when the token is unset or the failure is transient; a JSON-bodied `401\|403` (and any other exit-2 defect with a token present) exits 2; runner propagates any non-zero hook exit | P2 | No — `fail_or_skip` soaks every class; `run-migrations.sh` converts any hook non-zero into `::warning` | Keep; one condition in `fail_or_skip` + the caller |
| Run the hook on every migration run (not only when `applied > 0`) | P2 (re-run after a credential fix reloads instead of dead-ending; every release liveness-checks the credential) | No | Keep (spec-flow P1) |
| Add `SUPABASE_ACCESS_TOKEN` to `verify-required-secrets.sh` | P2 for the *absent-in-prd* case (which the soak rule deliberately treats as "never opted in") | No — REQUIRED[] lists only `NEXT_PUBLIC_*` | Keep (observability-coverage P1) |
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
- `apps/web-platform/scripts/run-migrations.sh` — post-apply block becomes: run the hook unconditionally after the `Migration run complete:` line; `hook_rc=0; bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`; `if [[ "$hook_rc" -eq 2 ]]; then echo "::error title=Supabase rejected the migration credential::Migrations applied this run: ${applied}. The schema-cache refresh was refused (see the error above), so new tables may 404 in the app for ~10 min after the next deploy. Fix the token, then re-run this job — it will not re-apply migrations, but it will retry the refresh."; exit 2; elif [[ "$hook_rc" -ne 0 ]]; then echo "::error title=Schema reload hook failed (rc=${hook_rc})::Migrations applied this run: ${applied}. postgrest-reload-schema.sh exited ${hook_rc} — a bug or a missing script, not a credential problem."; exit "$hook_rc"; fi`; rewrite the two preceding comments (the `--best-effort` rationale now reads "soaks only a missing token or a transient upstream error; with a token present a rejected credential or config defect exits 2 and is propagated so the job goes red on every run, applied or not (#8028); the hook runs on every run so a re-run after a credential fix reloads"); delete the "any non-zero exit it returns is itself a bug" paragraph.
- `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` — new helper `plant_reload_stub "$tmp"` writing an executable `$tmp/scripts/postgrest-reload-schema.sh` from a **quoted** heredoc (`<<'STUB'` — an unquoted one expands `$(dirname "$0")` at plant time into the *test's* directory and would `touch` a file inside the live repo, and freezes `${FAKE_RELOAD_HOOK_RC:-0}` to `0`, making R2/R4 vacuous): `#!/usr/bin/env bash` / `touch "$(dirname "$0")/../hook-ran"` / `exit "${FAKE_RELOAD_HOOK_RC:-0}"`, with a comment naming #8028; called from `make_temp_tree` **and** from T3 (which hand-builds its tree with `mkdir`/`cp` outside `make_temp_tree` and would otherwise exit 127 once the hook is unconditional); the fake `psql` (existing unquoted heredoc, so write `\${FAKE_ALREADY_APPLIED:-0}`) returns `1` for the `count(*) FROM public._schema_migrations WHERE filename` query when `FAKE_ALREADY_APPLIED=1`; new cases **R1** (probe off, apply, hook rc 0 → runner exit 0, no `::error`, `$tmp/hook-ran` present), **R2** (probe off, apply, `FAKE_RELOAD_HOOK_RC=2` → runner exit 2 and output contains `::error title=Supabase rejected the migration credential::`), **R3** (`FAKE_RELOAD_HOOK_RC=127` → runner exit 127 and output contains `::error title=Schema reload hook failed (rc=127)::`), **R4** (`FAKE_ALREADY_APPLIED=1` so `applied=0`, `FAKE_RELOAD_HOOK_RC=2` → runner exit 2, `$tmp/hook-ran` present — the hook runs and fails the run even when nothing was applied). All fake env (`FAKE_RELOAD_HOOK_RC`, `FAKE_ALREADY_APPLIED`, `MIGRATION_SCHEMA_PRECONDITION_PROBE=0` for R1–R3 whose fixture references a missing table) goes on the `env -i` line of each case — the harness strips the ambient environment. Vacuity floor `[[ $((PASS + FAIL)) -lt 5 ]]` → `-lt 9`. Header comment updated to say the suite also covers the post-apply reload hook.
- `apps/web-platform/scripts/verify-required-secrets.sh` — append `SUPABASE_ACCESS_TOKEN` to `REQUIRED=( … )` with a comment: `# Management-API PAT for the post-migration PostgREST reload (#8028). Lives in the prd root only; its absence is soaked by the reload hook as "never opted in", so this list is where prd drift goes red.` The header comment's "required NEXT_PUBLIC_* secret" wording becomes "required build/runtime secret".
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` and `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` — regenerated via `python3 scripts/lint-shell-trace-credential-refusal.py --write-baseline` and `--write-baseline-d` (full-tree, no `--changed`); the diff must be exactly the removal of the `apps/web-platform/scripts/postgrest-reload-schema.sh` row in each.
- `scripts/lint-supabase-deprecated-endpoints.sh` — refresh the `run-migrations.sh` allowlist reason (date `2026-09-13`, "runner messages/comments name SUPABASE_ACCESS_TOKEN around the post-apply hook; delegates to postgrest-reload-schema.sh, which is pinned"); add a one-line comment beside the assembly regex: `# SUPABASE_PAT intentionally retained after #8028 — a resurrected consumer must still enter the assembly.`
- `apps/web-platform/docs/migration-rollback.md` — "Requires `SUPABASE_PAT` in Doppler" → "Requires `SUPABASE_ACCESS_TOKEN` (Doppler `prd` root, inherited by every `prd_*` branch; for a dev target read it from `prd_terraform` — run the script with `--help` for the exact one-liner)"; note that a rejected token now exits 2 even under `--best-effort` and that the migration runner retries the refresh on every run, so re-running a red migration job after rotating the token reloads the cache (#8028).
- `knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` — `## Token`: replace the present-tense "does not use `SUPABASE_PAT`, which returns HTTP 401…" with "`SUPABASE_PAT` was retired in #8028 (dead in every config); `SUPABASE_ACCESS_TOKEN` is the sole Management-API credential."
- `knowledge-base/engineering/operations/secret-scanning.md` — `### SUPABASE_ACCESS_TOKEN (CLI / sbp_)`: fan-out becomes "Doppler `prd` root (inherited by every `prd_*` branch) + the GH Actions secret via `terraform apply` of `github_actions_secret.supabase_access_token` + local exports"; add "rotation failure fails the prd migration job on the next release that applies a migration (#8028 made that loud); no `dev` config carries this token by design".
- `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` — §Prevention 3: append `[Updated 2026-09-13 — #8028]`: the token is `SUPABASE_ACCESS_TOKEN` (prd root; dev reads it from `prd_terraform`); `--best-effort` soaks only a missing token/URL or a transient error; a rejected credential exits 2 and fails a migration run that applied something. Keep the original sentences (historical record), do not re-instruct minting.

## Files to Create

None. (v1's separate runner test file was folded into `run-migrations-schema-probe.test.sh` at plan review; the Phase 3 retirement loop is run from a scratch file outside the repo, not committed.)

## Implementation Phases

Phases are ordered by dependency direction: the script's contract changes first, then its caller, then the live retirement, then docs. All tests are written RED first (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (work-time probes, no edits)

- `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 15 passed (baseline). `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` → 5 passed (baseline).
- `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → 2 violations (Rule A, Rule D) — the state this plan remediates.
- `curl --version | head -1` ≥ 7.55 (for `--header @-`).
- Re-run the thirteen-config presence sweep and the liveness probes from Research Insights (bearer on stdin); abort the retirement phase if any `SUPABASE_PAT` returns other than 401/403, or if `SUPABASE_ACCESS_TOKEN` from the `prd` root is not 200.

### Phase 1 — `postgrest-reload-schema.sh` + its test (RED → GREEN)

1. Add T15, T15b, T15c, T16, T16b, the T4 stdin/argv assertions, the T9 `--help` assertion, the fake-curl stdin drain, and `</dev/null` on every invocation; run → RED on T4, T9, T15, T15b, T15c, T16, T16b.
2. Rename `SUPABASE_PAT` → `SUPABASE_ACCESS_TOKEN` in the remaining fixtures.
3. Edit the script per Files to Edit (preamble, header, `scrub_pat`, the soak rule in `fail_or_skip`, precondition message, curl form, `401|403` arm with JSON-body discrimination). Run → 20 passed.
4. `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → `OK`. Regenerate both baselines with `--write-baseline` / `--write-baseline-d`; `git diff --stat` on the two baseline files shows one removed line each; full-tree lint → clean.
5. **Exercise the exact endpoint the hard arm will judge, before flipping the caller:** `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform --plain)" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` (strict, dev project) prints `postgrest-reload-schema: reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2xx)`. A schema-cache NOTIFY on dev is harmless and proves `POST /v1/projects/{ref}/database/query` accepts this token class.

### Phase 2 — `run-migrations.sh` + harness (RED → GREEN)

1. Add `plant_reload_stub` (quoted heredoc), call it from `make_temp_tree` and T3, add the `FAKE_ALREADY_APPLIED` branch to the fake `psql`, bump the vacuity floor; add R1–R4; run → still 5 existing passes, RED on R2/R3 (runner exits 0 with a warning) and R4 (hook not invoked at `applied=0`).
2. Edit the post-apply block; run → 9 passed. `bash scripts/lint-orphan-test-suites.sh` → clean (no new file).
2b. Append `SUPABASE_ACCESS_TOKEN` to `verify-required-secrets.sh` `REQUIRED[]`; `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh` → `ok SUPABASE_ACCESS_TOKEN` among the `ok` lines, exit 0.
3. `bash plugins/soleur/test/fixture-relative-assert.test.sh`; if any row moved, `--write-baseline` in the same commit and name the changed operand in the commit message.
4. `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` → exit 0 after refreshing the `run-migrations.sh` allowlist reason and adding the regex comment.

### Phase 3 — Live retirement (pipeline-performed; roots first, every config verified)

Run from the worktree once the code no longer references `SUPABASE_PAT`, **as a script file in the scratchpad** (`bash "$SCRATCH/retire-8028.sh"` — `exit 1` inside a function kills a pasted interactive shell). Values never reach argv or stdout; one Doppler listing per config yields both reachability and presence (no TOCTOU); every probe captures the body and is errexit-safe; "proven dead" means **401 with a `{`-prefixed body** (a WAF 403 proves nothing); a config whose value hash differs from the `dev` root's is refused (a live override is never deleted here); each config independently gated (`hr-bulk-delete-per-item-live-infra-role-check`):

```bash
#!/usr/bin/env bash
set -euo pipefail
case "$-" in *x*) echo "refusing under xtrace" >&2; exit 78 ;; esac
S="${SCRATCH:?scratch dir}"; umask 077
names() { doppler secrets --only-names --json -p soleur -c "$1" 2>/dev/null | jq -r 'keys[]'; }   # one listing per config
present() { printf '%s\n' "$2" | grep -qx "$3"; }                                            # $2 = listing, $3 = name
value() { doppler secrets get "$2" -p soleur -c "$1" --plain; }
hash_of() { value "$1" "$2" | { IFS= read -r t && [[ -n "$t" ]] && printf '%s' "$t"; } | sha256sum | cut -c1-16; }
probe() {  # $1=config $2=name → "http=<code> body=<first 40 bytes>" or probe-failed(...); token never in argv
  local code
  code="$(value "$1" "$2" \
        | { IFS= read -r t && [[ -n "$t" ]] && printf 'Authorization: Bearer %s' "$t"; } \
        | curl --disable --noproxy '*' -s -o "$S/probe-body" -w '%{http_code}' --max-time 30 --header @- https://api.supabase.com/v1/projects)" \
    || { printf 'probe-failed(rc=%s,http=%s)' "$?" "${code:-}"; return 0; }
  printf 'http=%s body=%s' "$code" "$(head -c 40 "$S/probe-body" | tr -d '\r\n')"
}
DEV_HASH="$(hash_of dev SUPABASE_PAT)"
retire() {
  local cfg="$1" listing rc=0 p
  listing="$(names "$cfg")"
  present "$cfg" "$listing" DOPPLER_CONFIG || { echo "$cfg: doppler unreachable or empty listing (positive control failed)"; exit 1; }
  present "$cfg" "$listing" SUPABASE_PAT || { echo "$cfg: SUPABASE_PAT already absent"; return 0; }
  [[ "$(hash_of "$cfg" SUPABASE_PAT)" == "$DEV_HASH" ]] || { echo "$cfg: SUPABASE_PAT value differs from the dev root (override with a different value) — refusing"; exit 1; }
  p="$(probe "$cfg" SUPABASE_PAT)"
  [[ "$p" == "http=401 body={"* ]] || { echo "$cfg: SUPABASE_PAT probe '$p' — not proven dead, refusing to delete (re-run if probe-failed)"; exit 1; }
  [[ "$cfg" == prd ]] && { present prd "$listing" SUPABASE_ACCESS_TOKEN || { echo "prd: SUPABASE_ACCESS_TOKEN absent — refusing"; exit 1; }; }
  doppler secrets delete SUPABASE_PAT -p soleur -c "$cfg" --yes >/dev/null || rc=$?   # stdout dumps the whole config (learning 2026-05-26)
  echo "$cfg: doppler secrets delete rc=$rc"; [[ "$rc" -eq 0 ]] || exit 1
  present "$cfg" "$(names "$cfg")" SUPABASE_PAT && { echo "$cfg: SUPABASE_PAT still present after delete"; exit 1; }
  echo "$cfg: SUPABASE_PAT deleted, verified absent"
}
for cfg in dev prd; do retire "$cfg"; done                                                                       # roots
for cfg in dev_personal dev_scheduled prd_cla prd_ghcr prd_kb_drift_walker prd_scheduled prd_terraform prd_workspaces_luks; do retire "$cfg"; done   # branches: expected "already absent"
for cfg in ci cli cli_ops; do l="$(names "$cfg")"; present "$cfg" "$l" DOPPLER_CONFIG || { echo "$cfg: unreachable"; exit 1; }; present "$cfg" "$l" SUPABASE_PAT && { echo "$cfg: unexpected SUPABASE_PAT"; exit 1; } || echo "$cfg: absent (never carried it)"; done
rm -f "$S/probe-body"
```

Record all thirteen per-config lines (two `deleted, verified absent`, eight expected `already absent`, three `absent`) plus the two `doppler secrets delete rc=` lines in the PR body. The prd root is live production configuration; the write is a deletion of a credential the vendor already rejects, scoped by name, hash-pinned, gated per item, with no replacement value written anywhere.

**Live negative control (after Phase 3, before ship):** `SUPABASE_ACCESS_TOKEN="sbp_$(printf 'x%.0s' {1..40})" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh --best-effort; echo "rc=$?"` must print `rc=2` with the `Supabase rejected SUPABASE_ACCESS_TOKEN` error — the real endpoint, a genuinely bad token, the soft-fail flag on. This is the assertion that would have caught the dead PAT.

### Phase 4 — Documentation sweep

Edit `migration-rollback.md`, the credential-rotation runbook, `secret-scanning.md`, and the 2026-05-21 learning per Files to Edit. Then the residual check: `git grep -n SUPABASE_PAT -- . ':!*.json' ':!knowledge-base/project/plans/' ':!knowledge-base/project/specs/' ':!**/archive/**' ':!knowledge-base/project/learnings/' ':!knowledge-base/engineering/architecture/decisions/' ':!knowledge-base/support/' ':!plugins/soleur/skills/work/SKILL.md'` returns only `scripts/lint-supabase-deprecated-endpoints.sh` (detector regex + header/allowlist prose), `scripts/lib/scrub-supabase-pat.sh` (file name / header prose), `scripts/rotate-supabase-db-credential.sh` (past-tense comment). Every remaining hit is a detector, a library name, or a historical record — not a consumer.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure surfaces are Soleur's own CI: a red `migrate` job that blocks a prd release (old code keeps serving against a backward-compatible schema). The user-facing artifact this plan *removes* is `PGRST205` errors on features that read a freshly-migrated table during the up-to-ten-minute window after a deploy.
- **If this leaks, the user's data is exposed via:** the account-scoped Supabase Management-API token, which reaches every project's database. This plan shrinks that exposure: the token leaves curl argv, gains an xtrace refusal, gains proxy/curlrc confinement, its dead twin is deleted from ten configs, and — after plan review — it is handed to no `pull_request`-triggered job and copied into no new config.
- **Brand-survival threshold:** `aggregate pattern` — the harm class is repeated transient degradation after migrations (every release, all users, ≤10 min), not a per-user breach; the credential surface is net-reduced.

## Observability

```yaml
liveness_signal:
  what: "The migrate job's exit status and annotations: the reload hook runs on every migration run (diverging from main's applied>0 gate); 'postgrest-reload-schema: reload acknowledged (ref=…, HTTP 2xx)' on success; a rejected credential prints '::error::postgrest-reload-schema: Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP 401|403)…' and fails the job with '::error title=Supabase rejected the migration credential::' whether or not a migration was applied."
  cadence: "per migration run — every prd release (web-platform-release.yml migrate job, applied or not), every push/PR run of tenant-integration.yml (dev: token absent by design → one '::notice::' line, not a warning), every rls-authz-fuzz.yml run (local stack: same notice)"
  alert_target: "prd: release-outcome classifies a failed migrate as non-delivery and emails ops@ via Resend (a Sentry event fires only if that email is not delivered); no Slack arm fires for a migrate failure. prd token ABSENT: verify-doppler-secrets job reds (verify-required-secrets.sh) before deploy, same release-outcome email. Dev CI: none by design (no credential) — the notice is informational."
  configured_in: ".github/workflows/web-platform-release.yml (migrate, verify-doppler-secrets, release-outcome), apps/web-platform/scripts/run-migrations.sh (post-apply block), apps/web-platform/scripts/postgrest-reload-schema.sh (fail_or_skip soak rule + 401|403 arm), apps/web-platform/scripts/verify-required-secrets.sh (REQUIRED[])"

error_reporting:
  destination: "GitHub Actions annotations (observability layer 6 — workflow run log) from the script (stderr '::error::…' with the scrubbed, control-byte-stripped, 512-byte-capped API response body and the Doppler config name) and from the runner (titled '::error'); prd non-delivery reaches ops@ by Resend email from release-outcome, with Sentry (NEXT_PUBLIC_SENTRY_DSN) as the fallback when the email is undelivered"
  fail_loud: "job exit code equals the hook's exit code (2) on every run where the credential was rejected; the annotation names SUPABASE_ACCESS_TOKEN, the Doppler config, and the resolved project ref"

failure_modes:
  - mode: "SUPABASE_ACCESS_TOKEN rotated/expired at the vendor (Management API 401/403 with a JSON body)"
    detection: "hook exits 2 under --best-effort; every migrate run goes red with '::error title=Supabase rejected the migration credential::' — the very next prd release, migration or not"
    alert_route: "prd: release-outcome → Resend email to ops@ (Sentry fallback)"
  - mode: "SUPABASE_ACCESS_TOKEN absent from the prd root (Doppler drift after retirement)"
    detection: "verify-required-secrets.sh prints '::error::Required secret missing from Doppler prd: SUPABASE_ACCESS_TOKEN' and the verify-doppler-secrets job reds before deploy (the reload hook itself would soak absence as 'never opted in')"
    alert_route: "release-outcome → Resend email to ops@"
  - mode: "Edge/WAF 401/403 without an API JSON body, curl network failure, 5xx, HTTP 000"
    detection: "hook exits 0 under --best-effort with '::warning::postgrest-reload-schema: … (best-effort: skipping)'; strict mode exits 1; PostgREST's natural ~10-min poll is the fallback"
    alert_route: "warning annotation only (by design — a retry-able class must not block a release); the next run retries because the hook runs on every run"
  - mode: "Wrong project ref / project not visible to the token (HTTP 404), unparseable NEXT_PUBLIC_SUPABASE_URL, curl missing — with a token present"
    detection: "hook exits 2 under --best-effort (the soak rule treats these as config defects once the environment opted in); the runner reds with the titled error; the resolved ref is echoed on stderr before the POST"
    alert_route: "prd: release-outcome → Resend email to ops@"
  - mode: "Doppler retirement loop refuses (probe not 401+JSON, probe-failed, positive control failed, hash mismatch, delete rc≠0, or still present after delete)"
    detection: "the Phase 3 script exits 1 naming the config and the reason before or immediately after the offending step"
    alert_route: "work-phase output; the PR does not reach ready until the loop's thirteen lines are recorded"

logs:
  where: "GitHub Actions run logs for web-platform-release.yml (migrate, verify-doppler-secrets) and tenant-integration.yml (Apply migrations to dev); token values never appear (stdin header + scrub_pat; no token in any PR job)"
  retention: "GitHub Actions default log retention (90 days)"

discoverability_test:
  command: "bash apps/web-platform/scripts/postgrest-reload-schema.test.sh"
  expected_output: "Results: 24 passed, 0 failed"
```

## Guard Contract

### Guard 1 — a rejected credential (or any config defect with a token present) fails the migration run

**Property.** Whenever `run-migrations.sh` runs with `SUPABASE_ACCESS_TOKEN` set and the reload hook meets a non-transient failure — a 401/403 carrying a JSON body, a 404, an unparseable/unset project URL, a missing `curl` — the migration run exits non-zero with a titled `::error` annotation, under `--best-effort` as well as strict mode, on every run whether or not a migration was applied; and with the token **unset**, or on a transient failure, the run stays green.

**Assembly.** Chokepoint one: `fail_or_skip` in `postgrest-reload-schema.sh` — every non-2xx outcome and every precondition failure exits through this one function, whose soak condition is `best_effort && (code == 1 || token unset)`; the HTTP-status `case` (arms `2??`, `401|403`, `4??`, `5??`, `*`) and the three precondition checks are its only callers, and the `401|403` arm's JSON-body test decides which code it passes. Chokepoint two: the single call site in `run-migrations.sh`'s post-apply block (`bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`, unconditional, followed by the `hook_rc` branch) — the only place the hook is invoked from a migration run; its exit code must reach the runner's `exit`. The three workflow callers (`web-platform-release.yml` migrate, `tenant-integration.yml` apply, `rls-authz-fuzz.yml` local) all reach the hook through that one call site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In `fail_or_skip`, drop the `-z "${SUPABASE_ACCESS_TOKEN:-}"` term so `best_effort` alone soaks every code (the guard's own dispatch — back to main's behaviour) | RED — T15, T15b, T16, T16b (each must exit 2 under `--best-effort` with a token) |
| 2 | In `fail_or_skip`, drop the `code == 1` term so transience is hard | RED — T8, T15c, T2 stays green only if the token term survives (must-PASS check) |
| 3 | In the `401\|403` arm, pass code 1 for the JSON-body case | RED — T15, T15b |
| 4 | In the `401\|403` arm, drop the JSON-body discrimination (always code 2) | RED — T15c (HTML-body 403 under `--best-effort` must exit 0; strict must exit 1) |
| 5 | Add a second arm `403)` above `401\|403)` that calls `fail_or_skip 1` (a second member after a compliant first) | RED — T15b |
| 6 | In `run-migrations.sh`, restore `if ! bash …; then echo "::warning …"; fi` (swallow the hook's exit) | RED — R2, R3, R4 |
| 7 | In `run-migrations.sh`, restore `if [[ "$applied" -gt 0 ]]` around the hook call | RED — R4 (`hook-ran` marker must exist and the run must exit 2 at `applied=0`) |
| 8 | In `run-migrations.sh`, replace `exit "$hook_rc"` in the non-2 branch with `exit 2` | RED — R3 (rc 127 must propagate as 127) |

**Harness rows.**

- Suite mutation that must RED: in the test's fake curl, stop rendering `$CURL_HTTP_CODE` (print only the body) — the empty code falls to the `*` arm (code 1) so T5, T12, T15, T15b, T16 (which assert `rc == 2`) fail; T4/T13b/T14 also fail on the missing `2??`.
- Suite mutation that must RED: in `run-migrations-schema-probe.test.sh`, make `plant_reload_stub` ignore `FAKE_RELOAD_HOOK_RC` and always `exit 0` — R2, R3, R4 fail.
- Suite mutation that must RED: write the stub from an unquoted heredoc — `FAKE_RELOAD_HOOK_RC` freezes to `0` at plant time; R2/R3/R4 fail (and no `hook-ran` may appear under the repo: assert `! test -e apps/web-platform/hook-ran`).
- Must-PASS non-canonical inputs the contract explicitly permits: HTTP 503 under `--best-effort` exits 0 (T8); token unset under `--best-effort` exits 0 with a `::notice::` (T2); HTML-body 403 under `--best-effort` exits 0 (T15c); a `--help` run under `bash -x` exits 78 (lint-covered, not a suite case).

## Infrastructure (IaC)

Phase 2.8 reviewed. This plan introduces **no** new infrastructure: no server, service, secret, DNS record, vendor account, or firewall rule. The only live-infrastructure write is the **deletion** of a dead, name-scoped Doppler secret that Terraform has never managed (`git grep 'resource "doppler_secret"' -- 'apps/web-platform/infra/*.tf'` names no `SUPABASE_*`), so there is no `.tf` resource to remove and importing a dead credential into state solely to destroy it would add a Terraform-held copy of a secret for no benefit. The one Terraform-managed artifact in this credential family — `github_actions_secret.supabase_access_token` (`apps/web-platform/infra/inngest.tf`, value from the `supabase_access_token` Terraform variable in Doppler `prd_terraform`) — is untouched, and after plan review no workflow change consumes it.

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
**Assessment:** (A) Blocking the prd deploy on a rejected credential is the correct blast radius: failure lands after apply, old code keeps running on a backward-compatible schema, `release-outcome` reports the non-delivery; the alternative trades that for ~10 min of `PGRST205` 500s for real users with no rollback lever. `verify-migrations` is skipped on a red `migrate` (acceptable). (B) Consumers beyond script/test: `run-migrations.sh` comment, `rotate-supabase-db-credential.sh` comment (already correct), the deprecated-endpoints allowlist reason text; both shell-trace baselines list the script and become false statements once it is clean — regenerate in the same PR; the test file needs a case for 401-under-best-effort=2. (C) The CTO's recommendation to harden all non-429 4xx was cut at plan review as machinery, then **re-admitted at deepen as one condition in `fail_or_skip`** (with a token present, every exit-2 defect is hard under `--best-effort`; the 429 carve-out stays out). (D) Fork PRs already fail on the Doppler-token check; the step-level env injection the CTO reviewed was subsequently **removed** on the architecture-strategist's `pull_request`-exposure finding. (E) No ADR: credential retirement plus failure-semantics tightening in one script; no new boundary.

### Operations

**Status:** reviewed
**Assessment:** Zero cost delta; `knowledge-base/operations/expenses.md` lists Supabase Pro + domain and the Inngest Micro project with no token rows — no ledger edit. Vendor-side revocation: the token is already dead at Supabase (401 everywhere); no public Management-API endpoint for PAT list/revoke is known, and the repo's own rotation runbook routes revocation through the dashboard — do not add a vendor step; state "already 401 at vendor" in the PR. Process: `secret-scanning.md` `### SUPABASE_ACCESS_TOKEN` is stale for the post-change topology; amend with the inherited-from-`prd`-root fan-out, the TF-published GH secret, and the blast-radius statement. Folded into Files to Edit.

**Brainstorm-recommended specialists:** none (no brainstorm).

## Plan Review Record

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto (devex lens); advisor consult (opus). Mechanical findings applied in this revision are summarised in the Overview. Taste / User-Challenge items routed to `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`: DC-1 (dev token sourcing declines both operator-offered arms — User-Challenge), DC-2 (DHH: relocate the soft-fail policy from the script's `--best-effort` flag into the caller — Taste, not applied), DC-3 (spec-flow/architecture: add a retry before classifying a non-2xx — Taste, not applied), DC-4 (DHH: drop the runbook/secret-scanning/learning doc edits from the critical path — Taste, not applied; COO asked for the runbook line).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` prints `Results: 24 passed, 0 failed` (15 existing + T15, T15b, T15c, T16, T16b; review added T15d empty-body, T15e hostile-body/straddle, T16c no-curl, T17 429). This covers: a dead-but-present token is loud (T15/T15b: 401/403 + JSON body under `--best-effort` → exit 2, stderr has `::error::`, `Supabase rejected SUPABASE_ACCESS_TOKEN` and `sbp_REDACTED`, no raw `sbp_` fixture, no `skipping`); opted-in config defects are loud (T16, T16b); absence and transience stay soft (T2 notice, T8, T15c); bearer on stdin, absent from argv (T4); `--help` carries the `prd_terraform` one-liner (T9).
- [ ] AC2 — `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` prints `Results: 9 passed, 0 failed` (5 existing + R1–R4). *Amended at review:* the stub reports via a stdout marker carrying its argv (R1 pins `--best-effort`), not a filesystem `touch`, so there is no live-tree side effect to assert against.
- [ ] AC3 — `git grep -c 'SUPABASE_PAT' -- apps/web-platform/scripts/postgrest-reload-schema.sh apps/web-platform/scripts/postgrest-reload-schema.test.sh apps/web-platform/scripts/run-migrations.sh apps/web-platform/scripts/run-migrations-schema-probe.test.sh` reports no matches for any of the four, and `git grep -c 'SUPABASE_ACCESS_TOKEN' -- apps/web-platform/scripts/postgrest-reload-schema.sh` ≥ 5.
- [ ] AC4 — `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 (the CI invocation) and `python3 scripts/lint-shell-trace-credential-refusal.py` (full tree) exits 0; `grep -c 'postgrest-reload-schema.sh' scripts/lint-shell-trace-credential-refusal.baseline.txt scripts/lint-shell-trace-credential-refusal-d.baseline.txt` reports 0 for each; `git diff --numstat origin/main...HEAD -- scripts/lint-shell-trace-credential-refusal.baseline.txt scripts/lint-shell-trace-credential-refusal-d.baseline.txt` shows `0 9` (A/B/C: the two files this PR cleaned — the reload script and `verify-required-secrets.sh` — plus seven stale rows for files sibling merges had already cleaned without regenerating, each verified lint-clean with no baseline) and `0 1` (D). *Amended at review from `0 1`/`0 1`: the generator is the source of truth.*
- [ ] AC5 — `grep -c "| curl --disable --noproxy '\*'" apps/web-platform/scripts/postgrest-reload-schema.sh` = 1; `grep -c -- '--header @-' apps/web-platform/scripts/postgrest-reload-schema.sh` = 1; `grep -c 'Authorization: Bearer \${SUPABASE' apps/web-platform/scripts/postgrest-reload-schema.sh` = 0; `grep -c 'tr -d' apps/web-platform/scripts/postgrest-reload-schema.sh` ≥ 1 (control-byte strip in `scrub_pat`); `grep -cE '"\$code" == "1" \|\| -z "\$\{SUPABASE_ACCESS_TOKEN:-\}"' apps/web-platform/scripts/postgrest-reload-schema.sh` = 1 (the soak rule).
- [ ] AC6 — `awk '/# Post-apply: force a PostgREST/{f=1} f' apps/web-platform/scripts/run-migrations.sh` contains `|| hook_rc=$?`, `exit "$hook_rc"`, `::error title=Supabase rejected the migration credential::` and `::error title=Schema reload hook failed (rc=`; `grep -c 'if \[\[ "\$applied" -gt 0 \]\]; then' apps/web-platform/scripts/run-migrations.sh` = 0 (the hook is unconditional); `grep -c 'any non-zero exit it returns is itself a bug' apps/web-platform/scripts/run-migrations.sh` = 0.
- [ ] AC7 — `bash scripts/lint-orphan-test-suites.sh` exits 0 and `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0 (baseline regenerated in the same commit if any row moved, with the changed operand named in the commit message).
- [ ] AC8 — `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` exits 0; `grep -c 'intentionally retained after #8028' scripts/lint-supabase-deprecated-endpoints.sh` = 1.
- [ ] AC9 — No `pull_request` job gains the token: `grep -c 'secrets.SUPABASE_ACCESS_TOKEN' .github/workflows/tenant-integration.yml` = 0 and `grep -c 'secrets.SUPABASE_ACCESS_TOKEN' .github/workflows/rls-authz-fuzz.yml` = 0. *Amended at review from "workflow diff empty":* review added an ABSENCE assertion for the token in `tenant-integration.yml`, hardened the pre-existing bearer-in-argv curl in `scheduled-inngest-health.yml`, and renamed the release job's required-secrets step.
- [ ] AC10 — `grep -c '^  SUPABASE_ACCESS_TOKEN$' apps/web-platform/scripts/verify-required-secrets.sh` = 1, and `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh` exits 0 printing `ok SUPABASE_ACCESS_TOKEN`.
- [ ] AC11 — Phase 1 step 5 evidence in the PR body: the strict-mode dev run printed `reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2` (prefix; 200 or 201). **And** the live negative control: `SUPABASE_ACCESS_TOKEN="sbp_$(printf 'x%.0s' {1..40})" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh --best-effort; echo "rc=$?"` printed `rc=2` with `Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP 401)` (pasted with the body scrubbed).
- [ ] AC12 — All thirteen Doppler configs verified, recorded in the PR body as the Phase 3 script's per-config lines; reviewer re-verification (one listing per config, positive control first): `for c in dev dev_personal dev_scheduled ci prd prd_cla prd_ghcr prd_kb_drift_walker prd_scheduled prd_terraform prd_workspaces_luks cli cli_ops; do l="$(doppler secrets --only-names --json -p soleur -c $c 2>/dev/null | jq -r 'keys[]')"; printf '%s\n' "$l" | grep -qx DOPPLER_CONFIG || { echo "$c: UNREACHABLE"; continue; }; printf '%s\n' "$l" | grep -qx SUPABASE_PAT && echo "$c: STILL PRESENT" || echo "$c: absent"; done` prints thirteen `absent` lines and no `UNREACHABLE`.
- [ ] AC13 — Same shape with `SUPABASE_ACCESS_TOKEN`: `present` for `prd` and its six branches, `absent` for `dev`, `dev_personal`, `dev_scheduled`, `ci`, `cli`, `cli_ops`; `gh secret list | grep -c '^SUPABASE_ACCESS_TOKEN'` = 1 (P5: no new copy).
- [ ] AC14 — Residual sweep: the Phase 4 `git grep` (with its pathspec exclusions, plus `':!knowledge-base/INDEX.md'`) lists no file other than `scripts/lint-supabase-deprecated-endpoints.sh` (detector regex), `scripts/rotate-supabase-db-credential.sh` (past-tense comment), and the two docs whose "retired in #8028" text AC15 requires (`supabase-db-credential-rotation.md`, `secret-scanning.md`). *Amended at review:* `scrub-supabase-pat.sh` never contained the literal; the doc hits are historical records, not consumers.
- [ ] AC15 — `grep -c 'SUPABASE_PAT' apps/web-platform/docs/migration-rollback.md` = 0 and `grep -c 'prd_terraform' apps/web-platform/docs/migration-rollback.md` ≥ 1; `grep -c 'Updated 2026-09-13 — #8028' knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` = 1; `grep -c 'retired in #8028' knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` = 1.
- [ ] AC16 — `bash scripts/test-all.sh` green at the `/ship` Phase 4 full-battery checkpoint (no TypeScript touched).
- [ ] AC17 — PR body uses `Closes #8028` (code, docs, and the Doppler deletion all land pre-merge), states "SUPABASE_PAT was already 401 at the vendor; no dashboard revocation step exists or is needed", and carries the `## Model Dissents (informational)` block that `/ship` renders from `decision-challenges.md`.

### Post-merge (operator)

None. The Doppler deletion is performed in the work phase by the pipeline (Implementation Phase 3); the first prd release exercises the new path (hook on every run) with the `prd` root's `SUPABASE_ACCESS_TOKEN` and needs no operator action.

## Test Scenarios

- Script, strict mode: token unset → 2 with the Doppler-config-naming message (T1); URL unset → non-zero (T3); malformed URL → non-zero (T7); 200 → 0 with endpoint + NOTIFY body in argv, bearer on stdin, bearer absent from argv (T4); 401 + JSON → 2 (T5); 503 → 1 (T6); 404 → 2 (T12); 000 → 1 (T13); custom-domain CNAME → correct ref (T13b); `SUPABASE_API_HOST` ignored (T14); curl rc 6 → 1 and token scrubbed (T11); `--help` → 0 mentioning `SUPABASE_ACCESS_TOKEN` and `-c prd_terraform --plain` (T9); unknown flag → 2 (T10); 403 + HTML → 1 (T15c strict half).
- Script, `--best-effort`: token unset → 0 + `::notice::` containing `skipping` (T2); 503 → 0 + warn (T8); 403 + HTML → 0 + warn (T15c); **401 + JSON → 2 + `::error::` with `sbp_REDACTED`, no `skipping` (T15)**; **403 + JSON → 2 (T15b)**; **404 + JSON with token → 2 (T16)**; **URL unset with token → 2 (T16b)**.
- Runner (schema-probe harness): applied, hook 0 → 0, `hook-ran` present (R1); applied, hook 2 → 2 + `Supabase rejected the migration credential` (R2); applied, hook 127 → 127 + `Schema reload hook failed (rc=127)` (R3); nothing applied, hook 2 → 2, `hook-ran` present (R4); the five existing probe cases unchanged with the stub planted (T3 included).
- Required-secrets: `verify-required-secrets.sh` under `doppler run -c prd` prints `ok SUPABASE_ACCESS_TOKEN`; the same script with `SUPABASE_ACCESS_TOKEN=` unset in a scratch env prints `::error::Required secret missing from Doppler prd: SUPABASE_ACCESS_TOKEN` and exits non-zero.
- Live: Phase 1 step 5 dev reload acknowledged; the post-retirement negative control (`rc=2`); Phase 3 script output (thirteen lines + two delete rc lines); Phase 0 re-probe of both tokens with the 401 body prefix `{"message":"Unauthorized"}` recorded.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Mint a new `SUPABASE_PAT` | Restores a redundant second account-level token; the issue's own recommendation is to retire it. |
| Copy the prd `SUPABASE_ACCESS_TOKEN` into Doppler `dev`/`dev_scheduled` (operator-offered arm) | `dev_scheduled` is consumed by a `pull_request` job: PR-authored SQL/shell would hold a credential that can run arbitrary SQL on prd (`hr-dev-prd-distinct-supabase-projects`). |
| Inject `secrets.SUPABASE_ACCESS_TOKEN` as step env in `tenant-integration.yml` (plan v1) | Same exposure — the job runs on `pull_request`; every existing consumer of that secret is `push`/`schedule`/`workflow_dispatch`-only. Removed at plan review (architecture P0). |
| Fail dev CI loudly on the absent token | Reds every migration-carrying PR forever for a credential CI must not hold; "fail loudly" in the issue is about a *present* dead token. |
| Keep the job green and mirror the rejection to Sentry from bash | Deploying over a stale schema cache produces `PGRST205` for real users for up to ten minutes; a delayed release is strictly safer, and `release-outcome` already reports a red `migrate`. |
| Harden all non-429 4xx via a second helper and a 429 carve-out (plan v1) | Cut at plan review (simplicity P1) as machinery; **re-admitted at deepen as a property of the single soak rule** (silent-failure-hunter P1: with a token present, a 404/unset-URL/no-curl soak is a masked defect) — no helper, no 429 arm (a 429 is exit 2 on main today and stays so; a rate-limited single NOTIFY has not been observed), one condition in `fail_or_skip`. |
| Move the soft-fail policy into `run-migrations.sh` and delete `--best-effort` (DHH) | Deletes a documented flag and rewrites T2/T8 for the same P2 outcome; the narrower change (one hard arm) is the smaller diff. Recorded as DC-2. |
| Retry once before classifying a non-2xx (spec-flow / architecture) | The hook now runs on every migration run, so a transient 403 costs one job re-run that reloads; a retry loop inside a 15-second best-effort hook is machinery for a case the JSON-body discrimination already narrows. Recorded as DC-3. |
| Downgrade a rejected credential to a warning on no-op runs (plan v2) | Most prd releases apply nothing, so the dead token would surface only as a warning on a green job — the exact class this issue opened on (silent-failure-hunter P1). Any non-zero hook exit now fails the run. |
| Source `scripts/lib/strip-log-injection.sh` from the script | The lib lives at the repo root, three directories up from `apps/web-platform/scripts/`; the byte set is six characters and is inlined in `scrub_pat` with the same octal-escape rule (precedent: the inline copy in `apply-inngest-rls-dev.yml`). |
| Run the reload hook as its own workflow step | The runner's titled annotation plus propagated exit code already attributes the failure. |
| Migrate the inline `scrub_pat` to `scripts/lib/scrub-supabase-pat.sh` | The lib's header explicitly defers migrating pre-existing copies to a separate sweep. |
| Delete the Doppler secrets via Terraform | Neither secret is Terraform-managed; importing a dead credential into state to destroy it adds a state-held copy for nothing. |
| Vendor-side revocation via Playwright | The token already returns 401 at the vendor — there is nothing to revoke that changes any behaviour. |

## Dependencies & Risks

- **Risk: a future `SUPABASE_ACCESS_TOKEN` expiry now blocks the very next prd release, migration or not.** Intended (that is the loud failure); old code keeps serving. Mitigation: `secret-scanning.md` rotation section names the inherited fan-out and the blast radius; the fix is one rotation (Doppler `prd` root + `terraform apply` for the GH secret) and a job re-run, which now reloads.
- **Risk: dev CI keeps skipping the reload.** Accepted and recorded (DC-1): PR-triggered jobs must not hold a prd-reaching credential; PGRST205 flakes in dev remain bounded by the ~10-min poll, exactly as since the PAT died.
- **Risk: the schema-probe suite goes red because the relocated runner has no hook file.** Addressed in Phase 2 step 1 (stub hook planted in `make_temp_tree`) before the runner change lands.
- **Risk: fixture-relative-assert baseline row moves.** AC7 regenerates in the same commit with the operand named.
- **Risk: `--header @-` on an old curl.** Phase 0 checks `curl --version` ≥ 7.55; CI runners ship 8.x; the production precedent already relies on it.
- **Risk: the Phase 3 script refuses on a config.** It exits before any delete (or immediately after a failed one), naming the config and reason; `probe-failed(...)` means re-run, a hash mismatch means a genuine override that this plan must not touch (file an issue), never skip the config. The PR is not marked ready until the thirteen lines are recorded.
- **Risk: a JSON-bodied 404 from a wrong ref now reds a release.** Intended: the ref is derived from the same `NEXT_PUBLIC_SUPABASE_URL` the app uses, so a wrong ref is a config defect the app would surface anyway; the resolved ref is echoed before the POST.
- **Dependency:** `doppler` CLI authenticated for project `soleur` with write access to the `dev` and `prd` roots (read probes succeeded in this session; the delete is the first write and surfaces a permission error, captured as `rc≠0`, before any state changes).

## References & Research

- Issue #8028; PRs #4286, #4320, #7858; issues #4285, #7797, #7873, #7966, #3364 (all verified live via `gh pr view`/`gh issue view`; #4320's diff touches the script and `lib/supabase-ref-resolver.sh`; commits `46defe086` = #4320, `be69fa947` = #4286).
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
