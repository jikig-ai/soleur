# Tasks: split the Inngest host Doppler token (ADR-282 addendum 2026-10-30, #9927 item 4)

Plan: `knowledge-base/project/plans/2026-11-01-feat-inngest-flip-token-split-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/decision-challenges.md` (CTO R1-R6, N1-N6)

Hard limits for every task: no `apply_target=inngest-host-replace` dispatch, no config-bundle build or digest promotion, no Hetzner or Doppler write, no token minted, no edit to an image carrier (see the plan's "Files NOT to Edit").

## Phase 1: Tests first (RED)

- [x] 1.1 Create `apps/web-platform/infra/inngest-flip-token.test.sh`
  - [x] 1.1.1 Section R: systemd-parser resolver over the unit population (census floor, drop-in merge across `<unit>.service.d`/`<prefix>-.service.d`/`service.d`, web-host drop-ins excluded)
  - [x] 1.1.2 Section X: `systemd-analyze --root=<dir> cat-config systemd/system/inngest-cutover-flip.service` cross-check plus a `systemd-run --user -p EnvironmentFile=... /usr/bin/env` last-wins leg (`systemctl --root cat` is refused by systemd; required in CI, loud counted skip where absent)
  - [x] 1.1.3 Section W: execute the guard item under `sh` with a recording phone-home stub; census anchored on `\$\{doppler_(flip_)?token\}`
  - [x] 1.1.4 Section O: execute the flip-write item in a temp dir, assert mode 600, `|| exit 1`, ordering before the arming item
  - [x] 1.1.5 Section S: path-occurrence census for `/etc/default/inngest-flip`
  - [x] 1.1.6 Mutation batteries for Guards 1 and 2 (rows and harness rows from the plan)
- [x] 1.2 Rewrite finding 1b in `apps/web-platform/infra/inngest-host.test.sh` (boot token `read`, flip token `read/write`, `name = "inngest-flip"`, block-scoped awk exiting at `^}`)
- [x] 1.3 Gate tests: `tests/scripts/test-inngest-host-replace-gate.sh`, `tests/scripts/test-inngest-host-shape-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts` (floor 15 to 16, both exclusion sets)
- [x] 1.4 `cloud-init-inngest-provision-unit.test.sh` G4: keep `guards == 2`, reword the message
- [x] 1.5 `inngest-boot-emitter.test.sh`: add `doppler_flip_token` to `RENDER_EXPR`; redactor fixture row (rewrite both hard-coded paths once each, stub `doppler` and `jq`)
- [x] 1.6 `cloud-init-user-data-size.test.ts`: one consistent 58-char (48-char body) `SECRET_LENGTHS` for both tokens (review round R7: the shared `doppler_token` stays 48; the inngest arm uses `INNGEST_SECRET_LENGTHS` with 58); floor-exit rows for the budget script
- [x] 1.7 `preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES` 90 to 91 with the required comment
- [x] 1.8 Tripwire test: no non-comment `DOPPLER_TOKEN`/`printenv`/`env`/`declare -p`/`export -p` in `inngest-cutover-flip.sh` (superseded by R14: the text tripwire `T-flipsh` is deleted; a runtime canary scan in `inngest-cutover-flip.test.sh` replaces it)
- [x] 1.9 `inngest.test.sh` comment row (Condition-less drop-in is deliberate); rehearsal-test assertion (read token only); phone-home dp-mask synthetic-token row
- [x] 1.10 Confirm every new or changed assertion is RED for the right reason

## Phase 2: Terraform

- [x] 2.1 `inngest-host.tf`: `doppler_service_token.inngest` to `access = "read"`; rewrite the comment (cite the ADR addendum by title, no `#6890`)
- [x] 2.2 `inngest-host.tf`: new `doppler_service_token.inngest_flip` (`inngest-flip`, `read/write`); `templatefile` var `doppler_flip_token`; refresh the stale MEASURED comment
- [x] 2.3 `inngest-provision-rehearsal/rehearsal.tf`: pass `doppler_flip_token = doppler_service_token.rehearsal.key` (read token; never arms the flip)
- [x] 2.4 `inngest-arm-write-token.tf`: rewrite the "Tracked as a follow-up" paragraph; disambiguate `FLIP_READ` from `inngest_flip`

## Phase 3: Cloud-init (`cloud-init-inngest.yml`)

- [x] 3.1 `write_files` drop-in `inngest-cutover-flip.service.d/10-flip-token.conf` (`[Service]` + unprefixed `EnvironmentFile=`; no Condition)
- [x] 3.2 Widen the first charset guard into a loop over both tokens
- [x] 3.3 Flip-file write item after the `/etc/default/inngest-server` chown: `( umask 0177 && printf ... ) || exit 1`
- [x] 3.4 Redactor by-value `vals+=` line (sed, never sourced)
- [x] 3.5 Phone-home dp-mask: add `.` to the body class (one byte)
- [x] 3.5b Comment refresh (`git grep -n 'read/write'`); no `${` or `%{` in new comments
- [x] 3.6 Re-measure after each edit (Phase 5 command)

## Phase 4: Gates and workflow

- [x] 4.1 `inngest-host-replace-gate.sh`: add the address to `def allow` (+ header sentence)
- [x] 4.2 `inngest-host-shape-gate.sh`: add to `def allow` and the `doppler_touched` class (+ header)
- [x] 4.3 `apply-web-platform-infra.yml` `inngest_host` job: insert the new `-target` before the last line; keep `2>&1 | tf_redact_random_ids` on the final line only; comment that the line is graph-redundant
- [x] 4.4 `inngest_host_replace` job: add the `inngest-userdata-budget.sh` step before the plan step; parity-test row for presence and order; correct the `inngest-host.tf` precondition comment

## Phase 5: Budget

- [x] 5.1 `inngest-userdata-budget.sh`: both stubs high-entropy (48-char bodies, 58 total), flip var added, `stored <= cap - 512` floor with an env seam (test asserts rc == 1 exactly) (review round R7: the floor is now 384 and the three other stubs are hash-derived; the seam can only raise it)
- [x] 5.2 Record stored bytes, cap headroom and margin under 32,300; `INNGEST_GZIP_BUDGET` stays 32,300

## Phase 6: Records

- [x] 6.1 ADR-282 build-record addendum (append-only, via `soleur:architecture`)
- [x] 6.2 C4: `doppler -> inngest` edge description in `model.c4`; run `plugins/soleur/test/c4-count-parity.test.sh` and the two C4 tests
- [x] 6.3 Runbook subsection (plus go-condition: green budget job on the dispatch SHA; drift-workflow note; flip-rotation caveat) in `inngest-server.md` (plan shape, replace-window impact, abort and rollback rule, three owner-only routes, rehearsal option, inngest-host abort-until-replace) (review rounds R9, R11, R13: the go-condition is now a PR-visible `inngest-userdata-budget` check the owner reads on the head commit, not a merge gate; "abort-until-replace" is qualified to a live host, with the state-to-dispatch matrix for absent-host states)
- [x] 6.4 PR body: lead with the merge-changes-nothing sentence; link the addendum; `Ref #9927`; cite #11816, #11817 and #11820

## Phase 7: Verification

- [x] 7.1 New suite, `inngest-host.test.sh`, provision-unit, boot-emitter, the two gate suites, parity and size tests
- [x] 7.2 `bash apps/web-platform/infra/run-registered-suites.sh` and `bash scripts/lint-orphan-test-suites.sh`
  - Recorded outcome (review round): no per-command exit code was recorded for these two commands. The evidence is commit `7fb0c7de32`: the repo ratchets were found by `scripts/test-all.sh --affected` and fixed there (workflow size gate, suite weight row, fixture operands).
- [x] 7.3 `inngest-userdata-budget.sh`; `mint-inngest-bootstrap-tag.sh --dry-run` expects `result=noop` (unshallow first)
- [x] 7.4 `git diff --stat origin/main...HEAD -- <Files NOT to Edit>` prints nothing
- [x] 7.5 `terraform fmt -check` and `terraform validate` if providers are cached (else report not run)
  - Recorded outcome: `terraform fmt -check` rc 0; `terraform validate` success on the main root and on the rehearsal root; `validate-infra-templates.sh` not run (needs cloud-init on PATH).

## Phase 8: Review rounds (rulings R7-R14 in `decision-challenges.md`)

- [x] 8.1 Fix round 1 (R7-R11): floor 384 B with all five stubs hash-derived, `--cap-only` on the replace job, replace-gate `doppler_token_touched` counter (R10), runbook first-replace steps and state-to-dispatch matrix, ADR limits, plan correction note
- [x] 8.2 Fix round 2 docs (R12-R14, Y2): the ADR residual sentence for the write guard (R12), the floor reworded as a PR-visible check and not a merge gate (R13), the text tripwire replaced by a runtime canary scan in the records (R14), runbook steps 1 to 7 (owner-run Tier-B commands, `--since` format, phone-home witness, abort deadline, cost rule, `aborted` outcome), decision-challenges pointers and R12-R14 rows
- [ ] 8.3 Fix round 2 code and tests (X2): `--cap-only` purpose rows, floor-seam hardening, canary scan, S-glob narrowing, R-g sibling check, replace-gate source pin; then the lead re-runs the combined suites, commits, runs a final verification pass, qa, compound and ship
