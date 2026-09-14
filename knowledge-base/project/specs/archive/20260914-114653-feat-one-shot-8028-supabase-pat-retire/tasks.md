# Tasks: retire the dead SUPABASE_PAT and migrate the PostgREST reload to SUPABASE_ACCESS_TOKEN (#8028)

Plan (v3, deepened): `knowledge-base/project/plans/2026-09-13-security-retire-dead-supabase-pat-plan.md`
Dissents: `knowledge-base/project/specs/feat-one-shot-8028-supabase-pat-retire/decision-challenges.md`

## Phase 0: Preconditions (probes, no edits)

- [x] 0.1 `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 15 passed; `bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh` → 5 passed (baselines).
- [x] 0.2 `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/scripts/postgrest-reload-schema.sh` → 2 violations (Rule A + Rule D) — the state to remediate.
- [x] 0.3 `curl --version | head -1` ≥ 7.55.
- [x] 0.4 Thirteen-config presence sweep (one `doppler secrets --only-names --json … | jq -r 'keys[]'` per config) + liveness probes (bearer on stdin, body captured, values never printed): every `SUPABASE_PAT` → `401` with body `{"message":"Unauthorized"}`; `SUPABASE_ACCESS_TOKEN` from the `prd` root → 200. Abort Phase 3 otherwise.

## Phase 1: postgrest-reload-schema.sh + test (RED → GREEN)

- [x] 1.1 Test RED: add T15 (401 + JSON body containing a 24-char `sbp_` fixture, `--best-effort` → exit 2, `::error::` + `Supabase rejected SUPABASE_ACCESS_TOKEN` + `sbp_REDACTED`, no raw fixture, no `skipping`), T15b (403 + JSON → 2), T15c (403 + HTML: strict → 1 `without an API JSON body`; `--best-effort` → 0 warn), T16 (404 + JSON, token set, `--best-effort` → 2), T16b (URL unset, token set, `--best-effort` → 2); `make_fake_curl` drains stdin to `${CURL_STDIN_FILE:-/dev/null}` FIRST (comment: SIGPIPE guard); T4 asserts bearer in stdin capture, `--header` `@-` in argv, bearer absent from argv; T9 asserts `-c prd_terraform --plain`; `</dev/null` on every `bash "$SCRIPT"` invocation.
- [x] 1.2 Rename `SUPABASE_PAT` → `SUPABASE_ACCESS_TOKEN` in all remaining fixtures/assertions (T1–T14); T2 keeps asserting `warn|skip`.
- [x] 1.3 Script: xtrace preamble after `set -euo pipefail` (rotate-script shape, exit 78).
- [x] 1.4 Script header: `Required environment:` → `SUPABASE_ACCESS_TOKEN` (prd root, inherited by every `prd_*` branch; no `dev` config by design); `Examples:` → prd form + the dev one-liner reading from `prd_terraform`; `--best-effort` description = soft-fail ONLY for absence (notice) and transience (warning), everything else with a token exits 2; `Exit codes` note.
- [x] 1.5 Script `scrub_pat` → `printf '%s' "${1:0:512}" | tr -d '\r\n\f\v\033\177' | sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g'` (+ comment: `::` runner commands, octal escapes only).
- [x] 1.6 Script `fail_or_skip` → the single soak rule: soft iff `best_effort == 1 && (code == 1 || SUPABASE_ACCESS_TOKEN unset)`; unset → `::notice::… (best-effort: skipping — no SUPABASE_ACCESS_TOKEN in this environment)`, transient → `::warning::… (best-effort: skipping)`; else `::error::` + `exit "$code"`. Delete `soft_warn`.
- [x] 1.7 Script precondition message names `DOPPLER_CONFIG` and points to `--help`; update the `# Scrub bearer tokens` / `# Endpoint is pinned` comments.
- [x] 1.8 Script curl call → `printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" | curl --disable --noproxy '*' --silent --show-error --request POST --url "$endpoint" --header @- --header "Content-Type: application/json" --data "$payload" --max-time 15 -w $'\n%{http_code}' 2>/dev/null`.
- [x] 1.9 Script `401|403)` arm: `[[ "$body" =~ ^[[:space:]]*\{ ]]` → `fail_or_skip 2 "Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP …) from Doppler config '…'. Rotate it per knowledge-base/engineering/operations/secret-scanning.md §SUPABASE_ACCESS_TOKEN. … Response: ${body}"`; else `fail_or_skip 1 "auth endpoint answered HTTP … without an API JSON body (edge/WAF?). Retry. …"`. Other arms unchanged.
- [x] 1.10 GREEN: `bash apps/web-platform/scripts/postgrest-reload-schema.test.sh` → 20 passed.
- [x] 1.11 Lint: explicit-path shell-trace lint → OK; regenerate baselines with `--write-baseline` and `--write-baseline-d` (full tree); diff = one removed row each; full-tree lint clean.
- [x] 1.12 Live endpoint probe (dev, strict): `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd_terraform --plain)" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh` → `reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 2xx)`; record for the PR body (AC11).

## Phase 2: run-migrations.sh + harness + required-secrets (RED → GREEN)

- [x] 2.1 Harness: `plant_reload_stub "$tmp"` from a QUOTED heredoc (`<<'STUB'`: `touch "$(dirname "$0")/../hook-ran"`; `exit "${FAKE_RELOAD_HOOK_RC:-0}"`), called from `make_temp_tree` AND from T3's hand-built tree; fake `psql` gains `\${FAKE_ALREADY_APPLIED:-0}` (filename count → `1`); vacuity floor `-lt 5` → `-lt 9`; header comment notes hook coverage.
- [x] 2.2 Test RED: R1 (apply, hook 0 → 0, `$tmp/hook-ran` present), R2 (apply, `FAKE_RELOAD_HOOK_RC=2` → 2 + `::error title=Supabase rejected the migration credential::`), R3 (`FAKE_RELOAD_HOOK_RC=127` → 127 + `::error title=Schema reload hook failed (rc=127)::`), R4 (`FAKE_ALREADY_APPLIED=1`, `FAKE_RELOAD_HOOK_RC=2` → 2, `$tmp/hook-ran` present). Fake env on the `env -i` lines; `MIGRATION_SCHEMA_PRECONDITION_PROBE=0` for R1–R3.
- [x] 2.3 Runner: hook runs unconditionally after `Migration run complete:`; `hook_rc=0; bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort || hook_rc=$?`; rc 2 → titled `Supabase rejected the migration credential` + `exit 2`; other non-zero → titled `Schema reload hook failed (rc=N)` + `exit "$hook_rc"`; rewrite the two comments; delete the "itself a bug" paragraph.
- [x] 2.4 GREEN: schema-probe suite → 9 passed; `test ! -e apps/web-platform/hook-ran`; `bash scripts/lint-orphan-test-suites.sh` clean.
- [x] 2.5 `apps/web-platform/scripts/verify-required-secrets.sh`: append `SUPABASE_ACCESS_TOKEN` to `REQUIRED[]` with the #8028 comment; header wording → "required build/runtime secret"; `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh` → `ok SUPABASE_ACCESS_TOKEN`, exit 0.
- [x] 2.6 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate baseline in the same commit if a row moved (name the operand in the commit message).
- [x] 2.7 `scripts/lint-supabase-deprecated-endpoints.sh`: refresh the `run-migrations.sh` allowlist reason (date 2026-09-13); add the `# SUPABASE_PAT intentionally retained after #8028 …` comment beside the assembly regex; `--check-highwater` → exit 0.

## Phase 3: Live retirement (pipeline-performed, from a scratch script file)

- [x] 3.1 Write the plan's Phase 3 script to `$SCRATCH/retire-8028.sh` verbatim and run it with `bash` (roots `dev`, `prd` first; one listing per config; positive control on `DOPPLER_CONFIG`; sha256 pin to the `dev` root's value; "proven dead" = `http=401 body={…`; `prd` requires `SUPABASE_ACCESS_TOKEN` present; `doppler secrets delete … --yes >/dev/null`; delete rc captured; re-list; then the eight branches; then `ci`/`cli`/`cli_ops`).
- [x] 3.2 Record the thirteen per-config lines and the two `doppler secrets delete rc=` lines for the PR body (AC12); on `probe-failed(...)` re-run; on a hash mismatch stop and file an issue (a genuine override is out of scope); never skip a config.
- [x] 3.3 Live negative control: `SUPABASE_ACCESS_TOKEN="sbp_$(printf 'x%.0s' {1..40})" doppler run -p soleur -c dev -- bash apps/web-platform/scripts/postgrest-reload-schema.sh --best-effort; echo "rc=$?"` → `rc=2` with `Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP 401)`; record (AC11).
- [x] 3.4 AC13 check: `SUPABASE_ACCESS_TOKEN` present in `prd` + six branches, absent elsewhere; `gh secret list` shows exactly one `SUPABASE_ACCESS_TOKEN`.

## Phase 4: Documentation sweep

- [x] 4.1 `apps/web-platform/docs/migration-rollback.md`: `SUPABASE_ACCESS_TOKEN` (prd root, inherited; dev via `prd_terraform` — see `--help`); rejected token exits 2 under `--best-effort`; the runner retries the refresh on every run so a re-run after rotation reloads.
- [x] 4.2 `knowledge-base/engineering/operations/runbooks/supabase-db-credential-rotation.md` `## Token`: "`SUPABASE_PAT` was retired in #8028 …".
- [x] 4.3 `knowledge-base/engineering/operations/secret-scanning.md` `### SUPABASE_ACCESS_TOKEN`: inherited-from-`prd`-root fan-out + TF-published GH secret + blast-radius line ("rotation failure reds the next prd release; no `dev` config carries this token by design").
- [x] 4.4 `knowledge-base/project/learnings/2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` §Prevention 3: `[Updated 2026-09-13 — #8028]` note; do not re-instruct minting.
- [x] 4.5 Residual sweep (plan Phase 4 `git grep` with exclusions) → only the lint, the scrub lib, and the rotate script remain (AC14).

## Phase 5: Verification

- [ ] 5.1 Walk AC1–AC17 in the plan; paste command outputs into the PR body (bodies scrubbed).
- [ ] 5.2 `git diff --stat origin/main -- .github/workflows/` is empty (AC9).
- [ ] 5.3 PR body: `Closes #8028`; "SUPABASE_PAT was already 401 at the vendor; no dashboard revocation step exists or is needed"; `/ship` renders `decision-challenges.md` as `## Model Dissents (informational)`.
