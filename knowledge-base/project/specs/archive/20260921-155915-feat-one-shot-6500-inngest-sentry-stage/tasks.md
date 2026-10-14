# Tasks: the dedicated soleur-inngest host reports its bootstrap-pull outcome on the Sentry stage: schema

Plan: `knowledge-base/project/plans/2026-09-21-feat-inngest-host-sentry-stage-emit-plan.md` (deepened 2026-09-21).
**Ref #6500. Never close it.** The PR body uses `Ref #6500` only (AC11). Run AC greps with GNU grep (`/usr/bin/grep`).

## 1. Tests first (RED)

- [ ] 1.1 Changes to `inngest-boot-emitter.test.sh`:
  - [ ] 1.1.1 Add `sentry_dsn="https://pubKEYx7@o1.ingest.invalid/42"` to the render map at `:222`.
  - [ ] 1.1.2 Bump the key-count floor and ceiling from **17 to 18**.
  - [ ] 1.1.3 Add the G2 cases (event shape; rendered BODY equals the raw BODY).
  - [ ] 1.1.4 Add the G3 cases (stub curl recording argv, stdin and body; a phone-home stub that **exits 3**; DSN
    missing, empty, malformed or payload-bearing).
  - [ ] 1.1.5 Add the G4 cases (rendered `inngest-redact.sh`). Implement every mutation row in-suite with a
    landed-diff check.
- [ ] 1.2 `cloud-init-inngest-bootstrap.test.sh` "Guard 1b":
  - [ ] 1.2.1 A per-arm extractor, comment-stripped, with line-count floors.
  - [ ] 1.2.2 Exactly one anchored call per arm, each ending in `|| true`.
  - [ ] 1.2.3 Assertions on the `write_files` entries and their modes.
- [ ] 1.3 `cloud-init-inngest-zot-pull-mutation.test.sh`: add G1 rows 1-8 (including 3a/3b) and 11-13.
- [ ] 1.4 Changes to `zot-soak-6122.test.sh`:
  - [ ] 1.4.1 Add `soleur-inngest=1` as the **first** key in `$HEALTHY` and in every inline spec that gets past
    `APP_ZOT` (including `:201`).
  - [ ] 1.4.2 Add a fixture-body parameter to `run_soak`.
  - [ ] 1.4.3 Update the "after #6500" fixture.
  - [ ] 1.4.4 Add G6 rows 1-10, with rows 6-7 applied as `sed` mutations of the relocated soak copy.
  - [ ] 1.4.5 Add G1 row 10 (the `HOST_NAME` literal equals the soak `host_name:` value).
- [ ] 1.5 Confirm every new case is RED on the unmodified tree.

## 2. Terraform threading

- [ ] 2.1 `inngest-host.tf`: add `sentry_dsn = var.sentry_dsn` to the templatefile map, with its rationale comment.
- [ ] 2.2 `inngest-userdata-budget.sh`: add a 128 B `sentry_dsn` stub and a header note.
- [ ] 2.3 Run `git grep -ln 'zot_pull_token *=' -- '*.sh' '*.ts' '*.py'`; no other inngest render maps are expected.
  Add `sentry_dsn: 128` to `SECRET_LENGTHS` only if `cloud-init-user-data-size.test.ts` reddens.

## 3. Host-side emitter (`cloud-init-inngest.yml`)

- [ ] 3.1 `write_files` `/etc/default/soleur-sentry-dsn`: mode 0600, content `SOLEUR_SENTRY_DSN='${sentry_dsn}'`.
- [ ] 3.2 `write_files` `/usr/local/bin/soleur-boot-emit`:
  - [ ] 3.2.1 Read the DSN with `sed`, never by sourcing the file.
  - [ ] 3.2.2 Validate its shape; on failure phone home `rc=nodsn` or `rc=baddsn` and make no curl call.
  - [ ] 3.2.3 Use two brace-free, read-only seams.
  - [ ] 3.2.4 Use the web-format BODY with the literal `HOST_NAME='soleur-inngest'`.
  - [ ] 3.2.5 Call `curl -K -` with `--connect-timeout 5 --max-time 8 --retry 1 --retry-max-time 15`.
  - [ ] 3.2.6 Phone home `sentry-emit-FAILED rc=<n>` when curl fails.
- [ ] 3.3 `inngest-redact.sh`: enumerate the DSN and its key explicitly, read via `sed` with a seam.
- [ ] 3.4 Add the two **foreground** call sites ending in `|| true`, using the bare name and single spaces.
- [ ] 3.5 Rewrite the comment at `:1420-1429`.

## 4. Soak tightening (fail-closed only)

- [ ] 4.1 Add `_zot_reports_sentry_stage` and AND it into the corroboration `if`.
- [ ] 4.2 Add the `INNGEST_ZOT` arm (`stage:"inngest_zot" host_name:"soleur-inngest"`) after `APP_ZOT`.
- [ ] 4.3 Update the prose in the header, the trailer and the PASS line.
- [ ] 4.4 Verify AC6 (the pre-existing guards are byte-identical).

## 5. Architecture record

- [ ] 5.1 ADR-096 amendment dated 2026-09-21 (#6500):
  - [ ] 5.1.1 The bake decision and the host-pinned denominator.
  - [ ] 5.1.2 The DSN-rotation coupling.
  - [ ] 5.1.3 Supersession pointers at the 2026-08-13 bullet (`:1104-1113`) and at `:343`.
- [ ] 5.2 `model.c4`:
  - [ ] 5.2.1 Add the `inngest -> sentry` edge.
  - [ ] 5.2.2 Rewrite the "Deliberately NO `inngest -> sentry` edge" comment block (`:712-722`) and change the emitter
    count from three to four.
  - [ ] 5.2.3 Run the C4 syntax, render and count-parity tests.

## 6. Verification

- [ ] 6.1 Run the four infra suites, the soak suite, `inngest-userdata-budget.sh` and `cloud-init-user-data-size.test.ts`.
- [ ] 6.2 Run `terraform validate`, and record the payload delta in the PR body.
- [ ] 6.3 Check the PR body: `Ref #6500`, no closing keyword (AC11), and a note that delivery needs a window.

## Post-merge (operator window)

- [ ] PM1 Complete the `## Downtime & Cutover` pre-dispatch check (the `INNGEST_CUTOVER_FLIP` state), then dispatch
  `inngest-host-replace` with `-f reason=…`. There is no `confirm` input. Never dispatch `inngest-host`.
- [ ] PM2 Confirm the Sentry `inngest_zot` event with `host_name:soleur-inngest`, **and** the matching Better Stack
  marker. The Better Stack check is required before `RESULT: PASS`, because the Sentry event can be forged.
- [ ] PM3 #6500 stays open until an operator posts `RESULT: PASS`.
- [ ] PM4 Once `ZOT_SOAK_START` is pinned, the soak's `INNGEST_ZOT` count must be at least 1.
