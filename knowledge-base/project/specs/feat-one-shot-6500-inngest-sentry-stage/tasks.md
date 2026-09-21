# Tasks: the dedicated soleur-inngest host reports its bootstrap-pull outcome on the Sentry stage: schema

Plan: `knowledge-base/project/plans/2026-09-21-feat-inngest-host-sentry-stage-emit-plan.md`. **Ref #6500. Never close
it.** The PR body uses `Ref #6500` only (AC11).

## 0. Precondition

- [ ] 0.1 Verify `KillMode` in the `cloud-final.service` shipped with the host's Ubuntu 24.04 cloud-init (upstream
  `systemd/cloud-final.service.tmpl`), and record the line and version in the PR body (AC0).
- [ ] 0.2 If it is not `KillMode=process`, switch the Phase 3.4 call sites to foreground `… || true`.

## 1. Tests first (RED)

- [ ] 1.1 `inngest-boot-emitter.test.sh`: add `sentry_dsn` to the render map at `:222`, then add the G2 cases
  (event shape, and rendered BODY equals raw) and the G3 cases (stub curl, `SOLEUR_SENTRY_DSN_FILE`,
  `SOLEUR_INNGEST_PHONE_HOME`).
- [ ] 1.2 `cloud-init-inngest-bootstrap.test.sh`: add a "Guard 1b" section with the G1 static rows over
  `DED_CODE_FILE`/`DED_BLOCK_FILE`.
- [ ] 1.3 `cloud-init-inngest-zot-pull-mutation.test.sh`: add the G1 mutation rows 1-13.
- [ ] 1.4 `inngest-host.test.sh`: add the G4 redaction cases with a fixture DSN whose key is short and non-hex.
- [ ] 1.5 `zot-soak-6122.test.sh`:
  - [ ] 1.5.1 Add `soleur-inngest=1` as the first key in `$HEALTHY` and in every inline spec that gets past `APP_ZOT`
    (including `:201`).
  - [ ] 1.5.2 Update the "after #6500" fixture to carry both call sites.
  - [ ] 1.5.3 Add the G6 rows 1-11.
- [ ] 1.6 Confirm every new case is RED on the unmodified tree.

## 2. Terraform threading

- [ ] 2.1 `inngest-host.tf`: add `sentry_dsn = var.sentry_dsn` to the templatefile map, with its rationale comment.
- [ ] 2.2 `inngest-userdata-budget.sh`: add a 128 B `sentry_dsn` stub and a header note.
- [ ] 2.3 Run `git grep -ln 'zot_pull_token *=' -- '*.sh' '*.ts' '*.py'` and update any other hand-kept inngest
  render map.

## 3. Host-side emitter (`cloud-init-inngest.yml`)

- [ ] 3.1 Add `write_files` `/etc/default/soleur-sentry-dsn` with mode 0600.
- [ ] 3.2 Add `write_files` `/usr/local/bin/soleur-boot-emit`. It needs the two brace-free seams, `rc=nodsn`
  handling, the web-format BODY, a `curl -K -` call with its bounds, and `sentry-emit-FAILED` on failure.
- [ ] 3.3 `inngest-redact.sh`: add an explicit DSN and key enumeration with its seam.
- [ ] 3.4 Add the two call sites, backgrounded, using the bare name and single spaces.
- [ ] 3.5 Rewrite the comment at `:1420-1429`.

## 4. Soak tightening (fail-closed only)

- [ ] 4.1 Add `_zot_reports_sentry_stage` and AND it into the corroboration `if`.
- [ ] 4.2 Add the `INNGEST_ZOT` host-pinned denominator arm after `APP_ZOT`.
- [ ] 4.3 Update the prose in the header, the trailer and the PASS line.
- [ ] 4.4 Verify AC6: the pre-existing guards are byte-identical.

## 5. Architecture record

- [ ] 5.1 Add the ADR-096 amendment dated 2026-09-21, covering #6500 and the DSN-rotation coupling.
- [ ] 5.2 Add a `model.c4` edge `inngest -> sentry`, then run the C4 syntax, render and count-parity tests.

## 6. Verification

- [ ] 6.1 Run the five suites plus `inngest-userdata-budget.sh` and `cloud-init-user-data-size.test.ts`.
- [ ] 6.2 Run `terraform validate` and record the payload delta in the PR body.
- [ ] 6.3 Check the PR body: `Ref #6500`, no closing keyword (AC11), and the delivery-window note.

## Post-merge (operator window)

- [ ] PM1 Dispatch `inngest-host-replace` in an ADR-100 maintenance window. Do not dispatch `inngest-host`.
- [ ] PM2 Confirm the Sentry `inngest_zot` event and the matching Better Stack marker for that boot.
- [ ] PM3 #6500 stays open until an operator posts `RESULT: PASS`.
