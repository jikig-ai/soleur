# Tasks: restore-engine residue triage (#11667)

Plan: `knowledge-base/project/plans/2026-11-01-chore-restore-engine-residue-triage-11667-plan.md`
Constraint: no edit to `.github/workflows/apply-web-platform-infra.yml` (item 2b is held). PR body uses `Ref #11667` and `Ref #9757` only.

## Phase 1: RED fixtures
- 1.1 Add four rc-6 rows to `tests/scripts/test-registry-restore-from-ghcr.sh` (read-back, GHCR signature read, signature copy, sink signature read-back), two differently shaped unrecognised stderr strings.
- 1.2 Keep the MANIFEST_UNKNOWN rows as the rc-4 counterpart; add none that change them.
- 1.3 Each rc-6 row asserts rc 6, the site-specific phrase, no `NO FIXTURE`/`stub:` in the output, and the site's argv as the last crane call. Use unrecognised stderr that is not 500/429 text.
- 1.4 Add rc-4 counterparts: MANIFEST_UNKNOWN at the image read-back and the signature copy, plus one BLOB_UNKNOWN at the signature copy.
- 1.5 Raise `MIN_ASSERTIONS` 99 to 106. Run the suite; record per row that the four rc-6 rows fail (rc 4, not 6) and the counterparts and other 99 pass.

## Phase 2: engine (GREEN)
- 2.1 `scripts/registry-restore-from-ghcr.sh`: at each of the four sites add `NOTFOUND|BLOBMISSING) die 4` (message unchanged) and `*) die 6` (new message, distinct prefix, no single quote).
- 2.2 Do not touch the E05, E11, E12, E13 anchored lines.
- 2.3 Header: exit 5 row "unchanged" qualifier; exit 6 row "re-run is safe and resumable; the job does not retry 6"; copy-site `die 5` message "retrying unchanged will not clear it".
- 2.4 Engine suite green (`MIN_ASSERTIONS` 106); W9 wiring suite and pull-path-health suite green.

## Phase 3: battery rows
- 3.1 `tests/scripts/test-registry-gate-mutation-battery.sh`: add E45 to E48 (one per site, `die 6` back to `die 4`) and E49 to E52 (one per site, the `NOTFOUND|BLOBMISSING` arm to `die 6`), unique anchors.
- 3.2 Raise the anti-vacuity floor 70 to 78 at both edit sites (comparison and message text).
- 3.3 Commit the verified unit first.

## Phase 4: runbook (2c)
- 4.1 `registry-luks-recut-6929.md` row 5 ("not retryable as-is ... re-run only after the measure-first reading"), both "exits 1, 4 and 5 are not retryable" sentences.
- 4.2 Row 6 "re-run is safe and resumable; the job does not retry 6; re-dispatch by hand".
- 4.3 Row 4 clause (measured absence or mismatch; unclassified read faults exit 6).
- 4.4 "If the restore job fails": partial after exit 6; 7-day `registry-restore-pins` dependency; link to the retention deferral issue; mark expiry behavior unmeasured; no invented procedure.
- 4.5 Re-grep census subjects 1 to 3 and fix any orphaned sentence.

## Phase 5: wording (2d)
- 5.1 `scripts/registry-pull-path-health.sh` A2 exit-3 arm: "did not accept or serve a request" (re-check no test pins the old phrase).
- 5.2 ADR-169: append `## Amendment 2026-11-01` (exit-3 retry rationale, "wider set", pointer to the 2026-10-23 amendment, exit 4/6 classification). No body edits.

## Phase 6: verification (battery-armed)
- 6.1 Fast suites in the foreground; read each pass/fail line.
- 6.2 Launch the battery detached (`setsid -n`), own Bash call, explicit `cd`, `LOG` and `RC` exported in that call; confirm pid and cwd; arm Monitor on the rc file with a deadline and pid liveness check; read `pre-flight: 78/78 anchors resolve uniquely` first.
- 6.3 Read the rc file: only 0 is passed; rc 6 or queued CI means the required `test` CI context is the gate; never call a local run passed otherwise.

## Phase 7: ship hygiene
- 7.1 File two deferral issues (7-day artifact retention; NETWORK widening for 500 and 429) with re-evaluation criteria and a roadmap milestone; link the retention one from the runbook.
- 7.2 AC1 check: no `.github/workflows/` path in the diff. AC9: PR body greps clean of closing keywords; #11312, #10924 and the inngest-gate-witness files untouched.
- 7.3 Leave #11667 open; tracker comment: 2a, 2c, 2d done, 2b held.

## Held (not tasks): 2b
Seven workflow string edits R1 to R7, recorded in the plan under "Held: 2b". Lift needs the operator's written lift, a CTO ruling, an apply-trigger plan, one PR, net-negative bytes.
