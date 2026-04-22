# feat: Pre-deploy CI guard for required NEXT_PUBLIC_* secrets in Doppler prd

**Closes:** #2769
**Branch:** `feat-app-url-ci-guard`
**Worktree:** `.worktrees/feat-app-url-ci-guard/`
**Bundle:** `feat-app-url-hardening` — PR-B (of 2). PR-A (#2793) merged, retired `NEXT_PUBLIC_SITE_URL`.
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-22-app-url-hardening-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-app-url-hardening/spec.md` (FR3 + TR3)

## Overview

Add a pre-deploy CI job that fails the web-platform release when any required `NEXT_PUBLIC_*` secret is absent from Doppler `prd`. Closes the class of bug PR #2767 surfaced (silent Doppler drift → degraded payment flow). Required list is hand-maintained per brainstorm Decision #5 (YAGNI — revisit only on 2nd drift).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase (2026-04-22) | Plan response |
|---|---|---|
| Candidate list: 6 keys (`APP_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`) | Exhaustive grep `rg 'process\.env\.NEXT_PUBLIC_\w+' apps/web-platform/{app,server,lib,components,hooks,middleware.ts,sentry.*.config.ts,next.config.*}` returns 7 keys: the 6 candidates + `NEXT_PUBLIC_AGENT_COUNT`. | Freeze required-list at 6. `NEXT_PUBLIC_AGENT_COUNT` is **excluded**: it is Docker-build-arg-computed (`reusable-release.yml:307` derives it from `plugin_stats.agent_count`), not stored in Doppler, with a `\|\| "60+"` fallback in `components/connect-repo/ready-state.tsx:66`. `sentry.edge.config.ts` does not exist; only `sentry.client.config.ts` + `sentry.server.config.ts`. |
| TR3 placement: `reusable-release.yml` OR dedicated workflow | `reusable-release.yml` is shared with plugin release (no Doppler). `web-platform-release.yml` already runs `migrate` with `DOPPLER_TOKEN_PRD`. | New job `verify-doppler-secrets` in **`web-platform-release.yml`** (not the reusable). Runs parallel to `release`/`migrate`; `deploy.needs` extends to include it. |
| TR3 "block deploy via `needs:`" | Spec requires deploy BLOCKS ON guard, not serial ordering. | Guard runs parallel (fan-in into `deploy`). Keeps critical-path unchanged; matches existing `release`‖`migrate`→`deploy` shape. |

## Implementation

### Files to create

- `apps/web-platform/scripts/verify-required-secrets.sh` — guard script (executable)

### Files to edit

- `.github/workflows/web-platform-release.yml` — add `verify-doppler-secrets` job; extend `deploy.needs` and `deploy.if`

### Guard script

```bash
#!/usr/bin/env bash
set -o pipefail

# Assert every hand-maintained required NEXT_PUBLIC_* secret is exported in the
# current environment. Invoke via `doppler run -c prd -- bash <path>` so Doppler
# populates env before we read it.
#
# Drift policy: hand-maintained (brainstorm Decision #5). NEXT_PUBLIC_AGENT_COUNT
# is intentionally excluded — it is a build-time Docker ARG, not a Doppler secret.

REQUIRED=(
  NEXT_PUBLIC_APP_URL
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  NEXT_PUBLIC_SENTRY_DSN
  NEXT_PUBLIC_VAPID_PUBLIC_KEY
  NEXT_PUBLIC_GITHUB_APP_SLUG
)

missing=0
for key in "${REQUIRED[@]}"; do
  value="${!key:-}"
  if [ -z "$value" ]; then
    echo "::error::Required secret missing from Doppler prd: $key"
    missing=$((missing + 1))
  else
    echo "ok $key"
  fi
done

if [ "$missing" -gt 0 ]; then
  echo "::error::$missing required NEXT_PUBLIC_* secret(s) missing from Doppler prd"
  exit 1
fi

echo "All ${#REQUIRED[@]} required NEXT_PUBLIC_* secrets present in Doppler prd"
```

Notes:

- No `set -e` / no `set -u`. Rationale: (a) loop continues past each missing key so the error output enumerates every missing secret in one run, not just the first; (b) `set -u` + bash indirect expansion `${!key:-}` is brittle on bash 3.2 (macOS default) — dropping `-u` with explicit `:-` defaults keeps it portable while CI runs bash 5.x anyway.
- Empty-string treated as missing (same as unset). PR #2767 was "unset" specifically, but a truncated/empty Doppler value would be equivalently broken in the client bundle.

### Workflow diff (`web-platform-release.yml`)

Add one job (between `migrate` and `deploy`), extend `deploy.needs` + `deploy.if`:

```yaml
  verify-doppler-secrets:
    runs-on: ubuntu-latest
    concurrency:
      group: verify-secrets-web-platform
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      - name: Install Doppler CLI
        uses: dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3
      - name: Assert required NEXT_PUBLIC_* secrets present in Doppler prd
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}
        run: |
          doppler run -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh

  deploy:
    needs: [release, migrate, verify-doppler-secrets]   # was [release, migrate]
    # verify-doppler-secrets must succeed — skipped/failed blocks deploy (unlike
    # migrate which tolerates 'skipped' when no migrations changed).
    if: >-
      always() &&
      needs.release.outputs.docker_pushed == 'true' &&
      (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
      needs.verify-doppler-secrets.result == 'success' &&
      (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

- Pinned action digest copied verbatim from the existing `migrate` job (`dopplerhq/cli-action@014df23b...`).
- Single-line `run:` — no heredoc, satisfies `hr-in-github-actions-run-blocks-never-use`.
- Service token `DOPPLER_TOKEN_PRD` is config-scoped (`cq-doppler-service-tokens-are-per-config`); `-c prd` is redundant-but-harmless, matches the `migrate` pattern for consistency.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/scripts/verify-required-secrets.sh` exists, is executable (`chmod +x`), and shellcheck-clean when run locally (no CI enforcement — just clean before shipping).
- [x] Happy-path smoke: `cd apps/web-platform && doppler run -p soleur -c prd -- bash scripts/verify-required-secrets.sh` exits 0 with six `ok <KEY>` lines. Read-only invocation — the guard only reads env values. (Verified during work-phase: `dev` config lacks `NEXT_PUBLIC_SENTRY_DSN`, `NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `NEXT_PUBLIC_GITHUB_APP_SLUG`, so `prd` is the only config that round-trips the full list. Unrelated to this PR; tracking via the guard itself once it starts firing.)
- [x] Negative smoke: `env -i PATH="$PATH" bash apps/web-platform/scripts/verify-required-secrets.sh` exits 1 and emits exactly 6 `::error::Required secret missing from Doppler prd: NEXT_PUBLIC_*` lines plus the `::error::6 required...` summary line.
- [x] `.github/workflows/web-platform-release.yml` diff adds exactly one new job (`verify-doppler-secrets`) and updates `deploy.needs` + `deploy.if` only. No edits to `reusable-release.yml`.
- [x] Regression assertion: `rg 'NEXT_PUBLIC_SITE_URL' apps/web-platform/{app,server,lib,components,hooks,middleware.ts,sentry.*.config.ts,next.config.*}` returns zero (PR-A retired this var; guard intentionally omits it).
- [x] Exhaustiveness re-check (same grep used in Research Reconciliation) returns exactly `{AGENT_COUNT, APP_URL, GITHUB_APP_SLUG, SENTRY_DSN, SUPABASE_ANON_KEY, SUPABASE_URL, VAPID_PUBLIC_KEY}`. If any new key appears, update `REQUIRED` array (or document exclusion rationale) before merge.
- [ ] PR body includes `Closes #2769` (applied at `/ship` time).

### Post-merge (automatic)

- [ ] Merging this PR modifies `apps/web-platform/scripts/*` which matches `web-platform-release.yml`'s `paths: ['apps/web-platform/**']` push trigger — the release workflow **auto-fires on merge**. That auto-run IS the post-merge verification per `wg-after-merging-a-pr-that-adds-or-modifies`.
- [ ] Confirm via `gh run list --workflow=web-platform-release.yml --limit 1 --json conclusion,jobs` that the newly-added `verify-doppler-secrets` job has `conclusion: success`.
- [ ] If the auto-fire somehow skips (e.g., path filter evolves), explicit fallback: `gh workflow run web-platform-release.yml --ref main -f bump_type=patch -f skip_deploy=true` then poll `gh run list --workflow=web-platform-release.yml --limit 1`.

## Test Scenarios

Verified via the pre-merge happy-path + negative smokes above. Infrastructure-only PR — exempt from `cq-write-failing-tests-before` TDD Gate. The negative smoke IS the RED test, satisfied pre-merge. No unit-test framework added.

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Required-list drifts (new `NEXT_PUBLIC_*` added without array update). | Accepted per spec + brainstorm Decision #5. First missing-secret firing is the drift signal — same detection latency as auto-compute. The pre-merge exhaustiveness re-check AC is the prompt for every future author to re-evaluate. |
| R2 | Guard bug or Doppler CLI flake blocks ALL web-platform deploys. | Read-only check; failure modes are (a) token revocation (already shared with `migrate`, co-located blast radius), (b) CLI install action outage (pinned digest is stable). Emergency bypass: revert this PR. No feature flag needed. |
| R3 | `deploy.if:` expression syntax error causes all deploys to silent-skip. | Pre-merge `yamllint` (lefthook); post-merge auto-fire exercises the full chain — an if-expression typo surfaces on the first post-merge release. |
| R4 | `rg` in AC misses a config-file convention and list is not exhaustive. | Grep scope covers all runtime code paths (`app/`, `server/`, `lib/`, `components/`, `hooks/`), middleware, both sentry configs, and `next.config.ts`. Build-time ARG-only (Dockerfile) is out of scope by design — `NEXT_PUBLIC_AGENT_COUNT` is the lone example and is documented. |

## Open Code-Review Overlap

None (scanned 28 open `code-review` issues against the planned file paths).

## Domain Review

**Domains relevant:** none. Brainstorm's `## Domain Assessments` carried forward: "scoped infra/observability chore bundle, no user-facing capability". No specialists recommended.

## Rules Compliance

- `cq-doppler-service-tokens-are-per-config` → `DOPPLER_TOKEN_PRD` (config-scoped). ✓
- `hr-in-github-actions-run-blocks-never-use` → single-line `run:`, no heredoc. ✓
- `wg-after-merging-a-pr-that-adds-or-modifies` → auto-fire on merge + explicit fallback documented. ✓
- `cq-workflow-pattern-duplication-bug-propagation` → duplicated `migrate` pattern has no subshell-counter / piped-while / unguarded `gh api` idioms. ✓
- `cq-docs-cli-verification` → `doppler run -c prd --` is a standard flag; `dopplerhq/cli-action@014df23b` is the existing `migrate` pin. No fabricated tokens.
- `cq-write-failing-tests-before` → infrastructure-only exemption; the pre-merge negative smoke IS the RED test.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-22-feat-app-url-ci-guard-plan.md. Branch: feat-app-url-ci-guard. Worktree: .worktrees/feat-app-url-ci-guard/. Issue: #2769. Plan reviewed, implementation next.
```
