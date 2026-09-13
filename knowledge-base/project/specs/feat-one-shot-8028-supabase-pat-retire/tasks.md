# Tasks: retire the dead SUPABASE_PAT and migrate the PostgREST reload to SUPABASE_ACCESS_TOKEN (#8028)

Plan: `knowledge-base/project/plans/2026-09-13-security-retire-dead-supabase-pat-plan.md`
Dissents: `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`

## Phase 0: Preconditions (probes, no edits)

- [ ] 0.1 `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 15 passed; `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` → 5 passed (baselines).
- [ ] 0.2 `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → 2 violations (Rule A + Rule D) — the state to remediate.
- [ ] 0.3 `curl --version | head -1` ≥ 7.55.
- [ ] 0.4 Thirteen-config presence sweep + liveness probes (bearer on stdin, values never printed): every `SUPABASE_PAT` → 401/403; `SUPABASE_ACCESS_TOKEN` from the `prd` root → 200. Abort Phase 3 otherwise.

## Phase 1: postgrest-reload-schema.sh + test (RED → GREEN)

- [ ] 1.1 Test RED: add T15 (401 + JSON body, `--best-effort` → exit 2, `::error::` + `Supabase rejected SUPABASE_ACCESS_TOKEN`, no `skipping`), T15b (403 + JSON → 2), T15c (403 + HTML: strict → 1 `without an API body`; `--best-effort` → 0 warn); extend `make_fake_curl` with `cat > "${CURL_STDIN_FILE:-/dev/null}"`; T4 asserts bearer in stdin capture, `--header` `@-` in argv, bearer absent from argv; T9 asserts `-c prd_terraform --plain`; `</dev/null` on every `bash "$SCRIPT"` invocation.
- [ ] 1.2 Rename `SUPABASE_PAT` → `SUPABASE_ACCESS_TOKEN` in all remaining fixtures/assertions (T1–T14).
- [ ] 1.3 Script: xtrace preamble after `set -euo pipefail` (rotate-script shape, exit 78).
- [ ] 1.4 Script header: `Required environment:` → `SUPABASE_ACCESS_TOKEN` (prd root, inherited by every `prd_*` branch; no `dev` config by design); `Examples:` → prd form + the dev one-liner reading from `prd_terraform`; `--best-effort` description = soaks absence + transience, JSON-bodied 401/403 still exits 2; `Exit codes` note.
- [ ] 1.5 Script precondition message names `DOPPLER_CONFIG` and points to `--help`; update the two comments (`# Scrub bearer tokens`, `# Endpoint is pinned`) to name `SUPABASE_ACCESS_TOKEN`.
- [ ] 1.6 Script curl call → `printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" | curl --disable --noproxy '*' --silent --show-error --request POST --url "$endpoint" --header @- --header "Content-Type: application/json" --data "$payload" --max-time 15 -w $'\n%{http_code}' 2>/dev/null`.
- [ ] 1.7 Script `401|403)` arm: JSON body (`[[ "$body" == \{* ]]`) → scrubbed `::error::…Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP …) from Doppler config '…'…` + `exit 2` regardless of `best_effort`; else `fail_or_skip 1 "auth endpoint answered HTTP … without an API body (edge/WAF?). Retry. …"`.
- [ ] 1.8 GREEN: `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 18 passed.
- [ ] 1.9 Lint: explicit-path shell-trace lint → OK; regenerate baselines with `--write-baseline` and `--write-baseline-d`; diff = one removed row each; full-tree lint clean.
- [ ] 1.10 Live endpoint probe (dev, strict): `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform --plain)" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` → `reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2xx)`; record the line for the PR body (AC10).

## Phase 2: run-migrations.sh + harness (RED → GREEN)

- [ ] 2.1 Harness: `make_temp_tree` plants `$tmp/scripts/postgrest-reload-schema.sh` stub (touches `../hook-ran`, exits `${FAKE_RELOAD_HOOK_RC:-0}`); fake `psql` gains `FAKE_ALREADY_APPLIED` (filename count → `1`); header comment notes the hook coverage.
- [ ] 2.2 Test RED: R1 (apply, hook 0 → 0, `hook-ran` present), R2 (apply, hook 2 → 2 + `::error title=Supabase rejected the migration credential::`), R4 (`applied=0`, hook 2 → 0 + `::warning title=Schema-cache refresh refused on a no-op run::`, `hook-ran` present).
- [ ] 2.3 Runner: hook runs unconditionally after `Migration run complete:`; `hook_rc=0; bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`; `applied > 0` + rc≠0 → titled `::error` + `exit "$hook_rc"`; rc≠0 otherwise → titled `::warning`; rewrite the two comments; delete the "itself a bug" paragraph.
- [ ] 2.4 GREEN: schema-probe suite → 8 passed; `bash scripts/lint-orphan-test-suites.sh` clean.
- [ ] 2.5 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate baseline in the same commit if a row moved (name the operand in the commit message).
- [ ] 2.6 `scripts/lint-supabase-deprecated-endpoints.sh`: refresh the `run-migrations.sh` allowlist reason (date 2026-09-13); add the `# SUPABASE_PAT intentionally retained after #8028 …` comment beside the assembly regex; `--check-highwater` → exit 0.

## Phase 3: Live retirement (pipeline-performed)

- [ ] 3.1 Run the plan's Phase 3 loop verbatim (roots `dev`, `prd` first; positive control; 401/403 gate; `prd` requires `SUPABASE_ACCESS_TOKEN` present; `doppler secrets delete … --yes >/dev/null`; delete rc captured; re-verify; then the eight branches; then `ci`/`cli`/`cli_ops`).
- [ ] 3.2 Record the thirteen per-config lines and the two `doppler secrets delete rc=` lines for the PR body (AC11); on `probe-failed(...)` or any refusal, fix the cause and re-run the loop — never skip a config.
- [ ] 3.3 AC12 check: `SUPABASE_ACCESS_TOKEN` present in `prd` + six branches, absent elsewhere; `gh secret list` shows exactly one `SUPABASE_ACCESS_TOKEN`.

## Phase 4: Documentation sweep

- [ ] 4.1 `apps/web-platform/docs/migration-rollback.md`: `SUPABASE_ACCESS_TOKEN` (prd root, inherited; dev via `prd_terraform` — see `--help`); rejected token exits 2 under `--best-effort`; re-run retries the refresh.
- [ ] 4.2 `knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` `## Token`: "`SUPABASE_PAT` was retired in #8028 …".
- [ ] 4.3 `knowledge-base/engineering/operations/secret-scanning.md` `### SUPABASE_ACCESS_TOKEN`: inherited-from-`prd`-root fan-out + TF-published GH secret + blast-radius line.
- [ ] 4.4 `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` §Prevention 3: `[Updated 2026-09-13 — #8028]` note; do not re-instruct minting.
- [ ] 4.5 Residual sweep (plan Phase 4 `git grep` with exclusions) → only the lint, the scrub lib, and the rotate script remain (AC13).

## Phase 5: Verification

- [ ] 5.1 Walk AC1–AC16 in the plan; paste command outputs into the PR body.
- [ ] 5.2 `git diff --stat origin/main -- .github/workflows/` is empty (AC9).
- [ ] 5.3 PR body: `Closes #8028`; "SUPABASE_PAT was already 401 at the vendor; no dashboard revocation step exists or is needed"; `/ship` renders `decision-challenges.md` as `## Model Dissents (informational)`.
