# Tasks: split the Inngest host Doppler token (ADR-282 addendum 2026-10-30, #9927 item 4)

Plan: `knowledge-base/project/plans/2026-11-01-feat-inngest-flip-token-split-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/decision-challenges.md` (CTO R1-R6, N1-N6)

Hard limits for every task: no `apply_target=inngest-host-replace` dispatch, no config-bundle build or digest promotion, no Hetzner or Doppler write, no token minted, no edit to an image carrier (see the plan's "Files NOT to Edit").

## Phase 1: Tests first (RED)

- 1.1 Create `apps/web-platform/infra/inngest-flip-token.test.sh`
  - 1.1.1 Section R: systemd-parser resolver over the unit population (census floor, drop-in merge across `<unit>.service.d`/`<prefix>-.service.d`/`service.d`, web-host drop-ins excluded)
  - 1.1.2 Section X: `systemd-analyze --root=<dir> cat-config systemd/system/inngest-cutover-flip.service` cross-check plus a `systemd-run --user -p EnvironmentFile=... /usr/bin/env` last-wins leg (`systemctl --root cat` is refused by systemd; required in CI, loud counted skip where absent)
  - 1.1.3 Section W: execute the guard item under `sh` with a recording phone-home stub; census anchored on `\$\{doppler_(flip_)?token\}`
  - 1.1.4 Section O: execute the flip-write item in a temp dir, assert mode 600, `|| exit 1`, ordering before the arming item
  - 1.1.5 Section S: path-occurrence census for `/etc/default/inngest-flip`
  - 1.1.6 Mutation batteries for Guards 1 and 2 (rows and harness rows from the plan)
- 1.2 Rewrite finding 1b in `apps/web-platform/infra/inngest-host.test.sh` (boot token `read`, flip token `read/write`, `name = "inngest-flip"`, block-scoped awk exiting at `^}`)
- 1.3 Gate tests: `tests/scripts/test-inngest-host-replace-gate.sh`, `tests/scripts/test-inngest-host-shape-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts` (floor 15 to 16, both exclusion sets)
- 1.4 `cloud-init-inngest-provision-unit.test.sh` G4: keep `guards == 2`, reword the message
- 1.5 `inngest-boot-emitter.test.sh`: add `doppler_flip_token` to `RENDER_EXPR`; redactor fixture row (rewrite both hard-coded paths once each, stub `doppler` and `jq`)
- 1.6 `cloud-init-user-data-size.test.ts`: one consistent 53-char `SECRET_LENGTHS` for both tokens; floor-exit rows for the budget script
- 1.7 `preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES` 90 to 91 with the required comment
- 1.8 Tripwire test: no non-comment `DOPPLER_TOKEN`/`printenv`/`env`/`declare -p`/`export -p` in `inngest-cutover-flip.sh`
- 1.9 `inngest.test.sh` comment row (Condition-less drop-in is deliberate); rehearsal-test assertion (read token only); phone-home dp-mask synthetic-token row
- 1.10 Confirm every new or changed assertion is RED for the right reason

## Phase 2: Terraform

- 2.1 `inngest-host.tf`: `doppler_service_token.inngest` to `access = "read"`; rewrite the comment (cite the ADR addendum by title, no `#6890`)
- 2.2 `inngest-host.tf`: new `doppler_service_token.inngest_flip` (`inngest-flip`, `read/write`); `templatefile` var `doppler_flip_token`; refresh the stale MEASURED comment
- 2.3 `inngest-provision-rehearsal/rehearsal.tf`: pass `doppler_flip_token = doppler_service_token.rehearsal.key` (read token; never arms the flip)
- 2.4 `inngest-arm-write-token.tf`: rewrite the "Tracked as a follow-up" paragraph; disambiguate `FLIP_READ` from `inngest_flip`

## Phase 3: Cloud-init (`cloud-init-inngest.yml`)

- 3.1 `write_files` drop-in `inngest-cutover-flip.service.d/10-flip-token.conf` (`[Service]` + unprefixed `EnvironmentFile=`; no Condition)
- 3.2 Widen the first charset guard into a loop over both tokens
- 3.3 Flip-file write item after the `/etc/default/inngest-server` chown: `( umask 0177 && printf ... ) || exit 1`
- 3.4 Redactor by-value `vals+=` line (sed, never sourced)
- 3.5 Phone-home dp-mask: add `.` to the body class (one byte)
- 3.5b Comment refresh (`git grep -n 'read/write'`); no `${` or `%{` in new comments
- 3.6 Re-measure after each edit (Phase 5 command)

## Phase 4: Gates and workflow

- 4.1 `inngest-host-replace-gate.sh`: add the address to `def allow` (+ header sentence)
- 4.2 `inngest-host-shape-gate.sh`: add to `def allow` and the `doppler_touched` class (+ header)
- 4.3 `apply-web-platform-infra.yml` `inngest_host` job: insert the new `-target` before the last line; keep `2>&1 | tf_redact_random_ids` on the final line only; comment that the line is graph-redundant
- 4.4 `inngest_host_replace` job: add the `inngest-userdata-budget.sh` step before the plan step; parity-test row for presence and order; correct the `inngest-host.tf` precondition comment

## Phase 5: Budget

- 5.1 `inngest-userdata-budget.sh`: both stubs high-entropy (48-char bodies, 58 total), flip var added, `stored <= cap - 512` floor with an env seam (test asserts rc == 1 exactly)
- 5.2 Record stored bytes, cap headroom and margin under 32,300; `INNGEST_GZIP_BUDGET` stays 32,300

## Phase 6: Records

- 6.1 ADR-282 build-record addendum (append-only, via `soleur:architecture`)
- 6.2 C4: `doppler -> inngest` edge description in `model.c4`; run `plugins/soleur/test/c4-count-parity.test.sh` and the two C4 tests
- 6.3 Runbook subsection (plus go-condition: green budget job on the dispatch SHA; drift-workflow note; flip-rotation caveat) in `inngest-server.md` (plan shape, replace-window impact, abort and rollback rule, three owner-only routes, rehearsal option, inngest-host abort-until-replace)
- 6.4 PR body: lead with the merge-changes-nothing sentence; link the addendum; `Ref #9927`; cite #11816, #11817 and #11820

## Phase 7: Verification

- 7.1 New suite, `inngest-host.test.sh`, provision-unit, boot-emitter, the two gate suites, parity and size tests
- 7.2 `bash apps/web-platform/infra/run-registered-suites.sh` and `bash scripts/lint-orphan-test-suites.sh`
- 7.3 `inngest-userdata-budget.sh`; `mint-inngest-bootstrap-tag.sh --dry-run` expects `result=noop` (unshallow first)
- 7.4 `git diff --stat origin/main...HEAD -- <Files NOT to Edit>` prints nothing
- 7.5 `terraform fmt -check` and `terraform validate` if providers are cached (else report not run)
