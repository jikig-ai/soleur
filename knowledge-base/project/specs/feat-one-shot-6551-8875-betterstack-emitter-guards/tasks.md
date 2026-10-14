# Tasks — feat-one-shot-6551-8875-betterstack-emitter-guards

Plan: `knowledge-base/project/plans/2026-10-13-fix-6551-8875-betterstack-emitter-guards-plan.md`
Issues: #6551 (bug — the unadmitted-row mystery; semantic fix = the admission partition) · #8875 (chore — repo-wide emitter-selection census over every `betterstack-query.sh` caller)
Decisions: `decision-challenges.md` (this dir) — `pending - assumed:` rows may be superseded by a `soleur:engineering:cto` ruling at review.

## 1. RED first (`cq-write-failing-tests-before`)

- [ ] 1.1 Author `apps/web-platform/test/infra/vector-admission.test.sh`:
      parse `vector.toml` once via python3 `tomllib` into a source model
      (`include_units`/`exclude_units` merged into `_SYSTEMD_UNIT` maps,
      mirroring `JournaldConfig::merged_*_matches`); evaluate synthesized
      journald records under the documented semantics (includes = OR over
      field-value sets; excludes = drop on any match; absent include set =
      admit-all — pinned ABSENT); assert per-fixture admitting-source SETS
      and corpus-wide multiplicity <= 1. Corpus must include the verbatim
      #6551 row, the `-t systemd -p err` control shape, inngest-server rows
      at PRIORITY 6 and 0, systemd PRIORITY-6 Started/Stopped (`∅`), tagged
      rows at PRIORITY 4 and 2, container stdout/stderr for both container
      names, canary stderr, a vector.service PRIORITY-1 row, an untagged
      PRIORITY-6 row (`∅`). Structural pins: no `extra_args` on journald
      sources; S1/S2 `exclude_matches.SYSLOG_IDENTIFIER` tokenized-equal to
      the Source-4 include array; S1 `exclude_matches.CONTAINER_NAME` equal
      to union(S3, S3b includes); no `exclude_matches.PRIORITY` anywhere;
      sinks.betterstack `inputs` still exactly `["tag_journald", "tag_metrics"]`.
      Harness: `CASES` independent counter, `PASS+FAIL == CASES` conservation,
      literal `MIN_CASES` floor, instrument self-test, `printf`+`exit 1`
      floor reporting. HYGIENE: no bare `<<`/`<<<` token outside a real
      heredoc (assemble needles via `_lt='<'`); the tail floor sits outside
      any heredoc-blanked span and self-exits. **Expect RED** — the current
      config double-admits the tagged/crit/container-stderr fixtures and has
      no exclusion arrays.
- [ ] 1.2 Update `apps/web-platform/test/infra/vector-pii-scrub.test.sh`:
      Source-1 pin literal `["0", "1", "2", "3", "4"]` → `["3", "4"]` with
      rewritten reasoning; Source-2 pin `exclude_units` →
      `["inngest-server.service"]` with the vector.service-move rationale;
      `#7898` comment notes tagged crit rows single-ship via Source 4;
      ratchet `PII_SCRUB_MIN_CASES` to the measured post-change count.
      **Expect RED** on the two literal pins.
- [ ] 1.3 Update `apps/web-platform/infra/journald-config.test.sh`:
      `9963d` description text `{0..4}` → `{3,4}` (argv pin unchanged);
      widen `9963i` to accept canonical `exclude_matches.SYSLOG_IDENTIFIER`
      lines; add `9963m` — tokenized never-add of `systemd` over EVERY
      `exclude_matches.SYSLOG_IDENTIFIER` array (the silence direction);
      extend `9963i-bis` to refuse a bare `exclude_matches = {` table too;
      ratchet `MIN_TOTAL`. **Expect RED** on the widened `9963i` until
      `vector.toml` gains the new keys.
- [ ] 1.4 Author `scripts/lint-betterstack-emitter-read.sh` (guard) +
      `scripts/lint-betterstack-emitter-read.test.sh` (mutation battery):
      discovery over `git ls-files` minus knowledge-base/docs/md/test files
      and the guard pair itself; two-stage detection (raw match →
      comment-stripped invocation-shape lines, `#` strip for sh/yml/tf and
      `//`/`/*`/`*` strip for ts); classification OK-EMITTER
      (`SYSLOG_IDENTIFIER` check / `JSONExtractString` /
      `--control-require-field` / sourced `bs-emitter-row.sh` /
      `inngest-probe-row.sh` / `inngest-host-dark-gate.sh`) else
      `ALLOW[<path>]="<reason>"` else UNCLASSIFIED; STALE + BARE-REASON +
      MUST_FIND + `MIN_POPULATION` floor; exit 1 on violations, exit 2 on
      internal/floor errors. Battery rows: GREEN compliant reader, RED raw
      `--grep` reader, RED stale entry, RED bare reason, RED comment-only
      def "use", comment-only doc mention skipped (must-PASS), DISPATCH row
      (guard copy with the discovery grep deleted exits 0 on the
      unclassified fixture), floor-breach exit 2 via test override.
      **Sandbox battery green; live run RED** (emits the audit population).
- [ ] 1.5 Author `scripts/lib/bs-emitter-row.sh`: exports
      `BS_EMITTER_ROW_JQ` (`def bs_emitter_row($e): type == "object" and
      .SYSLOG_IDENTIFIER == $e;`) and `BS_EMITTER_MARKER_ROW_JQ`
      (`bs_emitter_row($e) and message startswith($m + " ")`), the
      `unset`/`source`/selftest load contract and `selector_unavailable` /
      `selector_failed` vocabulary of `inngest-probe-row.sh`, plus an
      executed `--selftest` mode printing its discoverability literal.
      Unit coverage lives inside the lint pair's battery (a reader sourcing
      it classifies OK-EMITTER; a tampered copy fails its own selftest).

## 2. Implement

- [ ] 2.1 Edit `apps/web-platform/infra/vector.toml` — Source 1:
      `include_matches.PRIORITY = ["3", "4"]`; add
      `exclude_matches.SYSLOG_IDENTIFIER = [<exact Source-4 tag set>]` and
      `exclude_matches.CONTAINER_NAME = ["soleur-web-platform",
      "soleur-egress-gw"]`. Source 2: `exclude_units =
      ["inngest-server.service"]`; add the same
      `exclude_matches.SYSLOG_IDENTIFIER` mirror. Do NOT touch the Source-4
      include array. Rewrite the DOUBLE-ADMISSION / OVERLAP paragraphs and
      retire both "dedupe fix belongs to #6551" / "#6551 tracks the semantic
      fix" sentences; extend the `systemd` never-add comment to name the
      exclude direction.
- [ ] 2.2 Run `vector validate --no-environment --config-toml
      apps/web-platform/infra/vector.toml` (VECTOR_BIN/`vector` on PATH;
      else rely on the CI step).
- [ ] 2.3 Run the census guard; disposition every discovered file:
      convert where an emitter predicate is straightforward, allowlist with
      a reason otherwise (any-emitter-is-the-property readers, host_metrics
      readers, hint-echo sites, the transport itself). Each converted reader
      gains `select(.SYSLOG_IDENTIFIER == "<tag>")` on the decoded row or
      sources `bs-emitter-row.sh`.
- [ ] 2.4 Register: two `run_suite` lines in `scripts/test-all.sh` (live +
      unit, beside the varq-ban pair); one `run:` line for
      `vector-admission.test.sh` in `.github/workflows/validate-vector-config.yml`.
      Verify `bash scripts/lint-orphan-test-suites.sh` is clean.
- [ ] 2.5 Docs: dated addendum in
      `knowledge-base/engineering/architecture/decisions/ADR-286-vector-journald-source-admits-by-or-and-the-systemd-path-control.md`
      recording the partition decision; confirm
      `cat-deploy-state.sh`'s `vector_config_identity` sha field still emits.

## 3. Green + verify

- [ ] 3.1 `bash apps/web-platform/test/infra/vector-admission.test.sh` green
      at the measured floor. (AC1)
- [ ] 3.2 `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` green
      (needs `SENTRY_USERID_PEPPER=fixture-…` and `VECTOR_BIN`); ratcheted
      floor. (AC4)
- [ ] 3.3 `bash apps/web-platform/infra/journald-config.test.sh` green;
      `MIN_TOTAL` ratcheted. (AC5)
- [ ] 3.4 `bash scripts/lint-betterstack-emitter-read.sh` exits 0 on the
      live tree; `bash scripts/lint-betterstack-emitter-read.test.sh` exits
      0. (AC6/AC7)
- [ ] 3.5 `bash scripts/lib/inngest-probe-row.test.sh`,
      `bash apps/web-platform/infra/fresh-boot-parity.test.sh`,
      `workspaces-boot-unlock.test.sh`, `luks-monitor.test.sh`,
      `inngest.test.sh` all exit 0. (AC8/AC10)
- [ ] 3.6 `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0. (AC11)
- [ ] 3.7 PR body: first line answers the production-mutation question
      (inert until apply / `inngest-host-replace`); `Closes #6551`,
      `Closes #8875`; `## Changelog` section present.
