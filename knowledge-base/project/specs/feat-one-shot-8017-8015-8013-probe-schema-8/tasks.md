---
title: "Tasks — inngest probe_schema=8 (#8017, #8015, #8013)"
branch: feat-one-shot-8017-8015-8013-probe-schema-8
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-10-fix-inngest-probe-schema-8-mount-devid-plan.md
---

# Tasks

Derived from the plan named above, after a four-agent review pass. Read the plan's `## Design` and
`## Guard Contract` before starting Phase 1 — the mutation matrices are the specification for the
tests, and they are written before the code they grade.

**Standing constraints for every task.** Do not dispatch `inngest-volume-recut` or any other
destructive `apply_target`. Do not write to Redis; the one authorized FLUSHALL stays unspent. New
emitter code is POSIX sh, because the battery executes the extracted probe body with `sh` and
`sh -n`.

**The single largest finding from review, carried here so it is not re-learned:** three guards were
originally written against a harness that, for six of fifteen rows, did not exist. Phase 1a builds
the harness before anything grades anything.

## Phase 0 — preconditions (no writes)

- [ ] 0.1 Confirm `origin/main` still carries `probe_schema=7` in
      `apps/web-platform/infra/inngest-bootstrap.sh` and `expected_schema="7"` in
      `tests/scripts/lib/inngest-host-dark-gate.sh`.
- [ ] 0.2 Read all three `.c4` model files and record the external-actor / external-system /
      container / access-relationship enumeration behind the plan's "no C4 impact" conclusion. No
      new ADR is created; the decision lands as an ADR-199 amendment.
- [ ] 0.3 Confirm `jq`, `curl` and `lsblk` are reachable from the probe's execution context. `jq`
      in particular arrives via `cloud-init-inngest.yml`'s `packages:` list, not via the OCI image,
      and the probe body calls it zero times today — which is why D3 guards on `command -v jq`.
- [ ] 0.4 Read the **live** `redis_key_patterns` value out of the warehouse with the
      `discoverability_test` command and paste it into this spec. The Phase 1 brace fixture corpus
      is derived from the shapes that row names, not from the one shape #8013 quoted.
- [ ] 0.5 Re-run and record the measurements the design rests on: the emitter's current histogram
      awk over a brace-shaped fixture (the leak); `lsblk -nso NAME,SERIAL` and `lsblk -nsdo SERIAL`
      against a partition (the parent walk, and the trap that `-d` does not collapse to one line —
      take the first NON-EMPTY value); a whole-`/dev/disk/by-id` walk (multi-valued: three aliases
      resolved to one device during planning).
- [ ] 0.6 Record the suite baselines measured during planning: dark gate 118/118 with `_FLOOR` at
      exactly 118 and 22 predicates against a floor of 21; emitter 324/324 against 305; pin
      drift-guard 163/163 with `unconditional=123 floor=123`; cutover flip 147/147. And confirm
      with `bash scripts/test-all.sh --enumerate all` that the three
      `apps/web-platform/infra/*.test.sh` suites are NOT in the enumeration.

## Phase 1a — build the missing harness (grades nothing yet)

- [ ] 1a.1 Add a `mutate_emitter` helper to `apps/web-platform/infra/inngest.test.sh` that seds a
      pristine copy of `inngest-bootstrap.sh`, re-extracts the probe body and re-runs it. That file
      has no mutation harness today (`grep -n 'mutate\|PRISTINE'` returns nothing), so without it
      every emitter-side mutation row is a hand-applied audit rather than a runnable row.
- [ ] 1a.2 Create `scripts/followthroughs/inngest-host-not-serving-7674.test.sh` — Guard 2 has no
      suite at all today. The probe is already fixturable through
      `INNGEST_SERVING_QUERY_BIN`, `INNGEST_SERVING_HOST`, `_HOST_NAME`, `_WINDOW`, `_LIMIT`.
- [ ] 1a.3 Register that suite in `scripts/test-all.sh` with an explicit `run_suite` line.
      Followthrough suites are not auto-globbed and an unregistered one reddens
      `scripts/lint-orphan-test-suites.sh`. Registration also places Guard 2 in the **required**
      `test-scripts` shard, better than the advisory job Guards 1 and 3 sit in.
- [ ] 1a.4 Add the ONE env seam the emitter needs: a by-id directory seam with a production
      default, following the `PROBE_DATA_MOUNT` / `PROBE_LATCH_DIR` convention. The device walk goes
      through `lsblk`, a binary, so it is stubbed on `PATH` like the existing `findmnt` stub — no
      second seam.

## Phase 1b — RED rows authorable against the current tree

- [ ] 1b.1 `tests/scripts/test-inngest-host-dark-gate.sh`: rename the mount predicate's cases and
      their `rows-g14*.json` filenames away from the collision with the coherence predicate, which
      shares both the `G14` label and those filenames today.
- [ ] 1b.2 Set `PD[probe_schema]=8`. Every fixture inherits it; left at 7, every `mutate` row's
      unmutated control collapses to `stale_schema`.
- [ ] 1b.3 Add both new fields to `PROBE_FIELDS` **at the tail, after `data_bytes`**, so they sit
      downstream of the histogram's `substr(out, 1, 400)` cap and cannot displace an existing field.
- [ ] 1b.4 Add the mount-pin rows: a real `findmnt -no SOURCE` shape (`/dev/sdb`), never a
      synthesized by-id string; the `--expected-volume-id` mismatch; each refusing sentinel; the
      must-PASS post-recut row carrying the mapper in `data_mount_src` and the expected alias in
      `data_mount_devid`; and Guard 1's harness rows H1–H3.
- [ ] 1b.5 `apps/web-platform/infra/inngest.test.sh`: add the `data_mount_devid` arms across all
      four mount shapes via a `PATH` stub for `lsblk` plus the by-id seam — raw device, mapper on a
      whole disk, mapper on a partition, two-level stacked mapper — plus `__NOMATCH__`,
      `__AMBIGUOUS__` and `__UNREADABLE__`, and the first-non-empty-value case.
- [ ] 1b.6 Add the `registry_fns` arms with an arg-aware GQL stub — note the existing `curl` stub
      returns `exit 7` unconditionally — covering a non-empty array, an empty array (`0`, a
      measurement) and an error envelope (`__UNREADABLE__`, never `0`).
- [ ] 1b.7 Replace the `redis-cli` key fixtures with the Phase-0-derived brace corpus. That stub is
      the only place in the repo that produces key names and all seven of its literals are
      `ns:kind:id`, which is why #8013 survived three schema generations. Include a colon-free brace
      group and a non-prefix tag. Assert the ULID is ABSENT and the category PRESENT.
- [ ] 1b.8 Add source assertions for the classes no stub can catch, following the #8005 precedent in
      that file: the shape of the new `lsblk`/`readlink` invocations, and the absence of a pipe that
      would swallow an exit status.
- [ ] 1b.9 `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh`: add the real-device arm
      resolving a genuine mapper through a genuine device tree to its backing device.
- [ ] 1b.10 Guard 2's fixture rows in the new suite: same-row conjunction, `registry_fns=0`,
      `__UNREADABLE__`, split-across-two-rows, the identity-filter row, and the harness rows
      including "the PASS row is older than the newest dark row".
- [ ] 1b.11 Correct the message/comparison drifts in files already being edited: the gate battery's
      distinct-predicate floor (says "floor is 20" against `-lt 21` and an ok message of "floor
      21"), and the emitter battery's `-eq 8` assertion claiming "three MORE fields than the
      never-zero list" while never comparing the two lists, and its sibling saying "the 5 store
      fields" while looping over 8.

## Phase 1c — RED rows whose anchor ships later

- [ ] 1c.1 Author Guard 1 row 1 (the G14 comparison) and Guard 2 row 1 (the `registry_fns`
      conjunct) now, expecting `mutate` to report "the mutation matched NOTHING" because the target
      text does not exist yet. Re-anchor each in the same commit that lands its target. Note also
      that a row reintroducing `$data_mount_src` into the G14 block must re-bind it locally:
      `mutate()` runs the mutated library under `bash -c` with no `set -u`.

## Phase 1d — anti-vacuity counters

- [ ] 1d.1 Raise every floor touched in the same edit that adds an assertion to its block. All are
      `-lt` refusals, so a floor set ABOVE the count fails the suite: `_FLOOR` equal to the new
      assertion count, `INNGEST_MIN_ASSERTIONS` at the new count, the distinct-predicate floor
      keeping its one of slack, and whichever of the pin drift-guard's five inventories is affected
      (Guard 1 `expected 50`, Guard A `expected 11`, Guard B `expected 9`, Guard D `expected 11`,
      Row 7 `expected 7`).
- [ ] 1d.2 Confirm every new row fails, and fails for the reason its matrix entry names.

## Phase 2 — GREEN: the emitter

- [ ] 2.1 `probe_schema=7` → `8`.
- [ ] 2.2 Bind `data_mount_devid` and `registry_fns` with `n/a` defaults beside the other
      unconditional-emit fields, so no path can leave either unbound.
- [ ] 2.3 Implement the resolution, placed **above** the inner `case "$data_mount_src"` (inside the
      `*)` sub-arm it would leave `data_mount_devid=n/a` on a dedicated row): bounded `lsblk -s` to
      the base device taking the first NON-EMPTY value, reverse-map constrained to the
      `scsi-0HC_Volume_*` namespace, four values (`scsi-0HC_Volume_<id>`, `__NOMATCH__`,
      `__AMBIGUOUS__`, `__UNREADABLE__`).
- [ ] 2.4 Implement the registry query, guarded on `command -v jq`, as a column-zero
      `readonly FUNCTIONS_GQL_QUERY='…'` line so the drift extractor's
      `grep -oE "^readonly FUNCTIONS_GQL_QUERY=.*"` can find it. `0` is a measurement; only a
      non-array, an error envelope, a transport failure or a missing `jq` is `__UNREADABLE__`.
- [ ] 2.5 Implement the hash-tag collapse before the two-segment reduction. The rule must be total
      over brace contents — a tag with no colon inside the braces must not survive verbatim — must
      handle a tag that is not at the start of the key, must be idempotent, and must leave
      `{queue}:queue:x` unchanged.
- [ ] 2.6 Add both fields to BOTH emit sites — the `logger` line and the phone-home fallback. The
      byte-identical-payload assertion is what catches a one-sided edit.
- [ ] 2.7 Update the probe unit's `Budget (#7695)` comment to the stated total: 53s plus `lsblk 5`,
      the by-id map at 5 and the registry `curl 5` = **68s** against the unchanged
      `TimeoutStartSec=120`. State the number.
- [ ] 2.8 Widen the `FUNCTIONS_GQL_QUERY` drift pin in
      `apps/web-platform/infra/inngest-cutover-flip.test.sh` from two files to three, and extend it
      to cover the `jq` parse expression — the property Guard 2 row 3 tests lives in the parse, not
      the query.

## Phase 3 — the image bump

- [ ] 3.1 Commit the carrier edits. Guard A is expected RED at this point.
- [ ] 3.2 Push the annotated tag `vinngest-v1.1.32` at that commit so
      `.github/workflows/build-inngest-bootstrap-image.yml` fires. A branch-push validation build is
      not available — its dispatch input validates against `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$`.
- [ ] 3.3 **Watch that run to completion and read the published digest before touching any pin
      site.** The workflow has no failure notification of any kind. If it fails, do not edit the
      pins: delete the remote tag (`git push origin :refs/tags/vinngest-v1.1.32`), fix the carrier,
      and re-tag at the corrected commit under the same number — the tag is disposable only while
      no image exists for it. Once an image exists the number is spent; a late correction is
      `vinngest-v1.1.33`, never a re-dispatch that moves the digest.
- [ ] 3.4 Commit the digest into all four pin sites: `IREF` and `ZIREF` in
      `apps/web-platform/infra/cloud-init-inngest.yml` and in
      `apps/web-platform/infra/cloud-init.yml`. Keep the window between 3.2 and 3.4 to one build
      run — the pin drift-guard's AC6 fails repo-wide, on `main` and on sibling PRs, while it is
      open.
- [ ] 3.5 Leave `cloud-init-inngest-zot-pull-mutation.test.sh` at `v1.1.24` — a deliberately stale
      negative control kept out of Guard B's population only by a glob accident. Do not sweep with
      a directory-wide `sed`.

## Phase 4 — GREEN: the off-host consumers

- [ ] 4.1 `tests/scripts/lib/inngest-host-dark-gate.sh`: `expected_schema="8"`.
- [ ] 4.2 Rewrite the G14 mount comparison to the single `data_mount_devid` predicate; demote
      `data_mount_src` to an audit field; ensure every non-matching value refuses.
- [ ] 4.3 Update the gate's prose in lockstep: the predicate index line, the `stale_schema` header
      note, the G14 rationale, the stale `BUMPED 3 -> 4` comment, and the `mount_mismatch`
      remediation text.
- [ ] 4.4 `.github/workflows/apply-web-platform-infra.yml` — **unconditional**. Sweep the
      `mount_mismatch` text AND the `probe_schema=3` recovery instruction in the `::error::` line,
      which tells a reader "a 0 means replacing will not help" in exactly the case where replacing
      is the fix. Also the `workflow_dispatch` input description that quotes the verdict vocabulary.
- [ ] 4.5 Extend the B12 emitter↔gate field contract loop to name `data_mount_devid`,
      `registry_fns`, and the two fields it currently omits (`redis_expires`, `redis_key_patterns`
      — a pre-existing gap from schemas 6 and 7). Add a separate assertion that `PROBE_FIELDS`
      equals the emitter's logger-line order as a **sequence**: B12 builds its comparison through
      `sort -u` and so does not pin emit order, which ADR-199 records as load-bearing.
- [ ] 4.6 `scripts/followthroughs/inngest-host-not-serving-7674.sh`: add the `registry_fns` conjunct
      to the same-row positive discriminator; update the header's two-field rationale to three;
      report the observed value on the `not_serving` path.
- [ ] 4.7 Add the producer↔consumer pin for `registry_fns`: assert by extraction across both files
      that the field name in the #7674 discriminator is byte-identical to the emitter's, failing
      loudly if either side comes back empty. Without it #8015 is the one fix that can silently do
      nothing, since the gate never reads the field.

## Phase 5 — records and follow-through

- [ ] 5.1 Amend ADR-199: C1's mount pin moved to `data_mount_devid`, why the original comparison
      was unsatisfiable, and that `data_mount_src` was retained as an audit field. Sweep its own
      stale `probe_schema=3` sequencing narrative in the same edit. No new ADR.
- [ ] 5.2 Correct ADR-142's stale `probe_schema=3` reference, and the same literal in
      `cloud-init-inngest-bootstrap.test.sh`'s Guard A comment (pre-existing gaps, fixed inline).
- [ ] 5.3 `knowledge-base/legal/audits/inngest-aof-destruction-record.md`: add a `data_mount_devid`
      row to the field table, and sweep the checklist's `data_mount_src=/dev/mapper/inngest-redis`
      line — the same post-recut string being demoted from predicate to audit field.
- [ ] 5.4 `scripts/encryption-posture-ledger.json`: the inngest volume entry's `live_verification`
      carries the `probe_schema=3` phrase and names `data_mount_src` as the substrate signal. Do
      not re-date `expires_on` (2026-10-22) — the entry carries an explicit note that extending it
      buys time rather than closing a gap.
- [ ] 5.5 `knowledge-base/engineering/operations/runbooks/inngest-server.md`: correct the pin count
      (three refs in one file → four across two), and add one line noting that
      `scheduled-inngest-health.yml` will keep reporting healthy on a row the recut gate refuses as
      `stale_schema`, by design.
- [ ] 5.6 Write the delivery follow-through probe under `scripts/followthroughs/`, its `run_suite`
      registration, its tracker directive (`follow-through` label, `earliest=<merge date>`,
      `secrets=BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`), and its `secrets=` wiring in
      `.github/workflows/scheduled-followthrough-sweeper.yml` if not already present. It exits 0
      only on a row from a `boot_id` other than `906c015b-…` carrying `probe_schema=8`,
      `data_mount_devid=scsi-0HC_Volume_106261946` and a non-empty `registry_fns`; exit 2 while the
      replace has not happened.
- [ ] 5.7 Run `plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 6 — full battery

- [ ] 6.1 `bash scripts/test-all.sh`, as its own invocation. It reaches the dark-gate suite, the new
      followthrough suite and the c4 parity suite — but NOT the three
      `apps/web-platform/infra/*.test.sh` suites.
- [ ] 6.2 Those three explicitly, since they run only in the advisory `deploy-script-tests` job:
      `bash apps/web-platform/infra/inngest.test.sh`,
      `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`,
      `bash apps/web-platform/infra/inngest-cutover-flip.test.sh`.
- [ ] 6.3 `sudo bash apps/web-platform/infra/inngest-redis-luks-loopback.test.sh`.
- [ ] 6.4 `python3 scripts/lint-guard-contract.py` and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.5 Walk `## Acceptance Criteria` and record the evidence for each, including one line per
      mutation-matrix and harness row with the RED output it produced.
