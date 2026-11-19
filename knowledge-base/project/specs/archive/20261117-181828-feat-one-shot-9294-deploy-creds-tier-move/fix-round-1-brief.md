# Fix round 1 brief — #9294 PR-A, 13-seat review synthesis

Worktree: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9294-deploy-creds-tier-move
Panel SHA: f668e1e42e. Implement EVERY item below; keep commits scoped (one commit is fine
for the whole fix round, message: `fix(infra): address review panel findings (#9294)`).

Settled decisions stand (no seat dissented). Do not re-litigate the two-PR split,
whole-project loader, or reviewerless deploy-channel.

## P1-1 — De-shape trio stems in `.github/actions/infra-credentials/infra-credentials.test.sh`

The trio-baseline census (`tests/scripts/test-trio-baseline-census.sh`) exempts NOTHING under
`.github/`, and matches names CASE-INSENSITIVELY with the regex
`(?<![A-Za-z0-9_])(?:TF_VAR_)?(STEM)(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])` over STEMS =
WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET. This file currently has
literal stems at ~657-660 (payload keys incl. `_NEXT`), ~703-706/745 (env_has args incl.
`TF_VAR_cf_access_client_secret` lowercase — ALSO a match), ~792 (dc6 regex). Each literal is a
counted tier-a key with no baseline row → T1 RED on merge.

FIX: introduce de-shaped name constants near the dc section header (~line 648):

    # The trio's real member names must NEVER appear literally in this file: it lives under
    # .github/, where the trio-baseline census exempts nothing — a literal stem here is a
    # counted tier-a key with no baseline row (the dc6 rule for action.yml applies to this
    # test too). The names are joined at runtime so the fixture still exercises the real
    # family. The literal `doppler secrets download` strings stay: a file that names no stem
    # holds no read-shape key.
    dc_n1="WEBHOOK_DEPLOY""_SECRET"
    dc_n2="CF_ACCESS_CLIENT""_ID"
    dc_n3="CF_ACCESS_CLIENT""_SECRET"
    dc_tf() { printf 'TF_VAR_%s\n' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"; }

Then rewrite every use:
- `dc_payload`: switch the `jq -n '{...}'` literal to `--arg` form so keys interpolate:
  `"$REAL_JQ" -n --arg n1 "$dc_n1" --arg n1x "${dc_n1}_NEXT" --arg n2 "$dc_n2" --arg n3 "$dc_n3" '{ DOPPLER_PROJECT:"soleur-deploy-channel", DOPPLER_CONFIG:"prd", DOPPLER_ENVIRONMENT:"prd", DOPPLER_TOKEN:"dp.st.META-FILTER-FIXTURE", ($n1):"dc-hmac-fixture", ($n1x):"dc-hmac-next-fixture", ($n2):"dc-cf-id-fixture", ($n3):"dc-cf-secret-fixture", TF_STATE_AWS_ACCESS_KEY_ID:"must-not-alias-id", TF_STATE_AWS_SECRET_ACCESS_KEY:"must-not-alias-secret", GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID:"must-not-latch-id", GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY:"must-not-latch-secret", GITHUB_APP_RUNTIME_DOPPLER_TOKEN:"dc-gar-must-not-deliver" }'`
  (the `DOPPLER_TOKEN` member is NEW — code-quality P3: proves META_FILTER against the real injected set)
- `env_has "WEBHOOK_DEPLOY_SECRET"` → `env_has "$dc_n1"`; `env_has "CF_ACCESS_CLIENT_ID"` → `env_has "$dc_n2"`;
  `env_has "TF_VAR_webhook_deploy_secret"` → `env_has "$(dc_tf "$dc_n1")"`;
  `env_has "TF_VAR_cf_access_client_secret"` → `env_has "$(dc_tf "$dc_n3")"` (everywhere incl. dc_green).
- Fail-message literals like `fail "dc3: no WEBHOOK_DEPLOY_SECRET"` → `fail "dc3: no $dc_n1"`.
- dc6: `grep -qE "$dc_n1|$dc_n2|$dc_n3" "$ACTION_YML"`.
VERIFY: `grep -cE 'WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET' infra-credentials.test.sh` must be 0 afterwards, and `bash tests/scripts/test-trio-baseline-census.sh` green.

## P1-2 — Ban `github_actions_*` secret/variable resources on the narrow-project files

Structural-enum (a2): `github_actions_environment_secret`, `github_actions_secret`,
`github_actions_variable`, `github_actions_environment_variable` are NOT in the census's
stateful-type ban set — one could TF-write a plaintext secret into Tier-A-readable state and
TF-seed the env secret, bypassing the operator mint. Find the type set near
`tests/scripts/test-infra-privileged-tier-census.sh:1688` (`G6_STATEFUL`/`G7_EXTRA`) and add
these four resource types to the set banned in the D11 narrow-project files
(soleur-infra-app/soleur-deploy-channel .tf), with a new landed mutant + MUTANT_FLOOR bump.
Check the census's own convention for where github_actions_* belongs (G6 vs G7 scope).

## P1-3 — G7i argv totality in the narrow arm

Structural-enum (b3): G7i checks presence of the right call + absence of `prd_terraform`, but a
second `doppler secrets download -p <other>` inside the arm parses green. Strengthen G7i in
`tests/scripts/test-infra-privileged-tier-census.sh` (~2106-2179): after extracting the narrow
arm, enumerate EVERY `doppler secrets|doppler run` invocation inside the arm text and require
each to carry `-p soleur-deploy-channel -c prd` (the arm may contain no other project arg).
Also add the clause-tagged failure + a landed mutant (e.g. append a second download call inside
the arm). Bump MUTANT_FLOOR and CENSUS_ROWS/FLOOR per the suite's ledger convention.

While there (code-quality P2): the G7i arm extractor counts `if`/`fi` at line-start — a
line-initial `fi` inside a heredoc or multi-line string mid-arm truncates the arm silently →
false-green. Two fixes: (a) header comment documents the invariant (the arm must not contain
line-initial `if`/`fi` tokens inside strings/heredocs — it is authored by us); (b) add a
totality companion — after extraction assert the arm contains the `source=tier_b_deploy_channel`
emit (the arm's terminal marker), so a truncated arm fails loud, not green. Also dedup the two
`[no-prd_terraform]` clause tags (~2160,2169) into distinct tags matching what each limb checks.

## P1-4 — DOPPLER_API_HOST / DOPPLER_VERIFY_TLS steering refusal in the loader

Structural-enum (b4): a caller-side `env: DOPPLER_API_HOST` (or `DOPPLER_VERIFY_TLS=false`) on
the loader job steers the authenticated `doppler` call — token exfil, pre-existing for the
broad arm too. In `.github/actions/infra-credentials/action.yml`, at the top of the load step
body (before the allowlist case, after `set -euo pipefail` / emit definition), refuse hard:

    # A caller-side DOPPLER_API_HOST or DOPPLER_VERIFY_TLS would steer EVERY authenticated
    # Doppler call this step makes — a token-exfil channel, not configuration. The job may
    # set neither; presence is a named refusal, never a warning.
    if [[ -n "${DOPPLER_API_HOST:-}" || -n "${DOPPLER_VERIFY_TLS:-}" ]]; then
      echo "::error title=infra-privileged::verdict=doppler_cli_env_refused — DOPPLER_API_HOST/DOPPLER_VERIFY_TLS set by the job would steer every authenticated call. Refused."
      exit 1
    fi

First `git grep -n 'DOPPLER_API_HOST\|DOPPLER_VERIFY_TLS' -- .github/` to confirm no existing
caller sets them (the META_NAMES list contains them only as payload-filter entries). Add a dc
row asserting the refusal fires before any call and exits non-zero.

## P2-1 — G7d env allowlist must admit `inngest-cutover` (5 seats)

`tests/scripts/test-infra-privileged-tier-census.sh` ~1891: `G7_ENV_OK` alternation
`(infra-privileged|deploy-channel|GH_ENVIRONMENT)` → add `inngest-cutover` (the settled decision
seeds DOPPLER_TOKEN_DEPLOY_CHANNEL on it). Same for the `GH_ENVIRONMENT=` pin at ~1904
(`^GH_ENVIRONMENT="(?:infra-privileged|deploy-channel)"$` → include `inngest-cutover`).
Fix the stale diagnostic at ~1900: `gh secret set without --env infra-privileged` →
`gh secret set without --env <a Tier-B env>` (matches the row title's `<Tier-B env>` phrasing).

## P2-2 — Census must prove `deployment_branch_policy { custom_branch_policies = true }` per env

G1d only proves the policy RESOURCE half; the block that ACTIVATES the named list is unparsed —
dropping it leaves the env admitting all branches (deploy-channel-environment.tf calls it
load-bearing). Add a clause (new check row, e.g. `G1d-bis`): for each `github_repository_environment`
resource naming a `want_policy` env, assert its body contains `deployment_branch_policy` with
`custom_branch_policies\s*=\s*true`. Parse raw like the existing code (comments-in-.tf is a
documented residual — terraform-target-parity.test.ts already strips comments and covers this
for the ratchet members). Add the block to the fixture's `github_repository_environment.deploy_channel`
(~2855-2870) so the fixture mirrors the real file. Add a landed mutant (drop the block → red).
Bump CENSUS_ROWS/FLOOR/MUTANT_FLOOR per ledger convention.

## P2-3 — New loader test rows dc7/dc8 + dc3 cardinality + misc (test-design P2 + P3s)

In `infra-credentials.test.sh` (after dc6):
- dc7 `deploy_channel_read_failed`: `run_loader "" "dp.st.LEGACY-FIXTURE" "" "$(dc_payload)" 7 false "soleur-deploy-channel" "dp.st.DEPLOY-FIXTURE"` → rc≠0, `said "verdict=deploy_channel_read_failed"`, `out_get source != legacy`.
- dc8 `deploy_channel_empty`: metadata-only payload `"$REAL_JQ" -n '{DOPPLER_PROJECT:"soleur-deploy-channel",DOPPLER_CONFIG:"prd",DOPPLER_ENVIRONMENT:"prd"}'` → rc≠0, `said "verdict=deploy_channel_empty"`.
- dc9 `doppler_cli_env_refused` (from P1-4): drive run_loader with `DOPPLER_API_HOST` set (add a
  9th positional arg or export via STUB_-style env — pick the file's own convention; run_loader's
  `env -i` whitelist means you must add it to the env list) → rc≠0, verdict named, calls file EMPTY.
- dc3: add call-cardinality `[[ "$(wc -l < "$LOADER_DIR/calls")" -eq 1 ]]` after the greps.
- `dc_mutant`: add a landed-in-region check mirroring census `mutate` — the diff between
  `$ACTION_YML` and `$mut` must mention the narrow arm (e.g.
  `diff "$ACTION_YML" "$mut" | grep -qE 'soleur-deploy-channel|DP_DEPLOY_CHANNEL'`), not just `cmp -s`.
- Thread `STUB_DEPLOY_PAYLOAD` through `run_loader`'s `env -i` (it's read by the stub but never
  passed — add `STUB_DEPLOY_PAYLOAD="${STUB_DEPLOY_PAYLOAD:-}"` to the env list), and use it in
  one dc row (e.g. serve a distinct payload proving the narrow read isn't answered by the broad
  fixture's names) or drop the knob — thread it.
- Bump the file's assertion count constant (118→146 becomes ~146→~160); keep arithmetic honest.

## P3 batch — action.yml

- Narrow arm: force the pre-split `TF_VAR_github_app_runtime_token_delivered` flag to false —
  inside the narrow arm before `emit source`, append
  `printf 'TF_VAR_github_app_runtime_token_delivered=false\n' >> "$GITHUB_ENV"` with a one-line
  comment (later lines win; the arm never delivers). Update dc4 to pin it false.
- `git-data-root-state-bucket` output description (~106-112): `""` also means "the narrow arm ran".
- Action `description:` preamble (~3-8): mention the third arm (`tier_b_deploy_channel`).
- Normalize the duplicated `${DP_PROJECT:-soleur-infra-privileged}` default (lines 173 + 228):
  `PROJECT="${DP_PROJECT:-soleur-infra-privileged}"` once; `case "$PROJECT"` and
  `if [[ "$PROJECT" == "soleur-deploy-channel" ]]`.
- Comment at ~263-265 "cannot drift in export shape" → soften ("kept byte-similar so the two
  arms share one export shape" — the mechanism is copy-parity pinned by dc3/dc4).
- ~226 comment "NO App-runtime opt-in" → note the delivered flag is forced false inside the arm.
- stderr parity (security P3): the broad arm redirects download stderr (an auth error can quote
  the token prefix); give the narrow download `2>"${RUNNER_TEMP:-/tmp}/deploy-channel-download.err"`.
- Narrow arm start: if DP_INFRA or DP_LEGACY are non-empty alongside the narrow project, emit a
  `::notice::` naming that broad-mode inputs are ignored in narrow mode.

## P3 batch — census / trio-baseline / docs

- `tests/scripts/test-trio-baseline-census.sh`: `PENDING_ENVS` (~226) — remove `deploy-channel`
  (it graduated into sibling TIER_B_ENVIRONMENTS; `PENDING_ENVS - SIB` is now just
  `inngest-cutover`). Update E1's title (~739, "plus only the pending name deploy-channel") and
  the `{"deploy-channel"}` carve-out (~738) to name `inngest-cutover`; update mutants c54/m54
  (~2445,2461) whose `want` text matches the E1 title.
- Plan `knowledge-base/project/plans/2026-11-16-9294-deploy-channel-creds-tier-move.md`: fix the
  premise "11 workflows bind secrets.<trio>" → 10 (git-history verified `apply-deploy-pipeline-fix.yml`
  has ZERO trio binds — task 2.1.10 is a no-op; annotate it). Add to the operator seed section:
  (a) post-seed `doppler secrets -p soleur-deploy-channel -c prd --only-names` asserting the key
  set equals exactly the trio family (user-impact P2 — the whole-project export's membership
  bound is the seed itself); (b) the `protection_rules` read-back must assert the EXACT object
  (`custom_branch_policies:true`, exactly one branch-type `"main"` entry, no tag-type policy).
- `tasks.md`: add explicit PR-B precondition line (live env + seeded token verified via
  `protection_rules` + `source=` canary before any consumer binds `deploy-channel`); note on 1.4
  that a SEPARATE `github -> doppler` edge was deliberate (the existing edge's env list names
  DOPPLER_TOKEN_INFRA_PRIVILEGED holders, which deploy-channel is not — pattern seat verified).
- `apps/web-platform/infra/deploy-channel-environment.tf`: (a) header cites "ADR-241 D3/D4" —
  match the precedent's citation style (infra-app-project.tf cites D3/D4 literally;
  infra-privileged cites "measured, M7") — pick the literal-correct form; (b) the GitHub env
  resources carry no `prevent_destroy` (matches precedent — env secrets die with the env): add a
  one-line comment naming it deliberate.

## Verification required before returning

- `bash tests/scripts/test-infra-privileged-tier-census.sh` — all rows green, mutants land.
- `bash .github/actions/infra-credentials/infra-credentials.test.sh` — green.
- `bash tests/scripts/test-trio-baseline-census.sh` — green (this is the P1 proof).
- `bun test plugins/soleur/test/terraform-target-parity.test.ts` — green.
- `git grep -cE 'WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET' .github/actions/infra-credentials/infra-credentials.test.sh` → 0.
- `git grep -n 'DOPPLER_API_HOST\|DOPPLER_VERIFY_TLS' -- .github/` → only META_NAMES/comment refs.
- Do NOT run `test-all.sh --affected` or any full gate — the lead runs it once at the end.
- Update floors/ledgers consistently; keep every mutant landing.
