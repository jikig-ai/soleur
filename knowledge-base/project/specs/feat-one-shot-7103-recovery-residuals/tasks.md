# Tasks — close #7103's R1–R5

Derived from `knowledge-base/project/plans/2026-08-01-fix-7103-recovery-residuals-r1-r5-plan.md`
(deepened 2026-08-01). Phase order is **risk-ranked**, not dependency-ranked: R1 first (highest
recurrence risk), R2 → R3 a hard dependent pair.

`lane: cross-domain` · `brand_survival_threshold: single-user incident` · `requires_cpo_signoff: true`

**Hard invariants — do not reorder around these:**
- 3.1 (drop-in shape gate) ships **before** 3.2 (the sudo grant). Granting a root restart of a unit
  whose config can be written unvalidated turns delivery into execution.
- R3 is never verified before R2 has landed **and applied**. Its measurement path runs through the
  component R2 repairs.
- Phase 1's suite lives inside the runner Phase 2 folds in, so Phase 1 is re-verified at the exit
  gate (task 8.1), not only when it is written.

---

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Run the full local suite on a clean tree; record the `N/N suites passed` baseline.
- [x] 0.2 List the registered infra suites with `… --list | grep -c '\.test\.sh$'` (expect 87 — **not**
      `| wc -l`, which returns 88 because the runner prints a header). Run them in full; record
      PASS/RED. Triage any pre-existing red under `wg-when-tests-fail-and-are-confirmed-pre` before
      Phase 2.
- [ ] 0.3 Run `.github/scripts/test/run-all.sh`; record `RAN` (expect 10, `MIN_SUITES=10`).
- [x] 0.4 Verify `python3` + `yaml` in the job that will run the R4 harness. **Decides Phase 5's home.**
- [x] 0.5 Confirm the liveness gate is still the final step of `cf-tunnel-ssh-bridge/action.yml`.
- [x] 0.6 Count `FILE_MAP` entries (expect 19); note the two stale "18 destinations" comments.
- [x] 0.7 Confirm `"source": "string"` is an accepted hook source.
- [x] 0.8 Re-derive the required-check list from the live ruleset.
- [x] 0.9 Enumerate every consumer of `cat-infra-config-state.sh` output.
- [x] 0.10 Read `infra-config-apply.sh`'s tail: state-write block, `.final` sentinel, post-write region.
- [x] 0.11 Read the sudoers file; record every alias's paired `User_Spec` line **and** its `server.tf`
      `remote-exec` grep assertion.
- [x] 0.12 Read `infra-config-install.sh`'s content gate and confirm its `/etc/default/*` scope.
      **Security precondition — do not start 3.2 without this.**
- [x] 0.13 Confirm repo visibility is PUBLIC (context for the 5.1 `::add-mask::`).

## Phase 1 — R1: make the invocation say who it is

- [x] 1.1 Add a per-hook `SOLEUR_DEPLOY_HOOK_ID` string source to `deploy` and `deploy-peer` in
      `hooks.json.tmpl`.
- [x] 1.2 Emit the 4-field `SOLEUR_DEPLOY_INVOCATION` marker in `ci-deploy.sh`, after the credential
      read and before `flock`. Closed vocabulary; truncated `script_sha`; no token bytes.
- [x] 1.3 Add the `else` branch to the credential `if [ -r … ]` that feeds `cred_file`. Distinguish
      absent from unreadable. **No second marker.**
- [x] 1.4 Add `zot_gate_degraded_event no_credential_source` to the one gate arm that lacks it.
      **This is half (b).**
- [x] 1.5 Leave the fail-open control flow untouched; add no new deploy-state reason enum.
- [x] 1.6 Extend `ci-deploy.test.sh`: marker on every path, each `cred_file` value reachable,
      degraded-event on absence, no fixture token in output, distinct hook IDs.
- [x] 1.7 **Re-file half (a) on #7103** with reproduction detail verbatim (both timestamps, both
      `ZOT_GATE` lines, the `IMAGE_PULL_FAIL` line, F1–F7, the marker as the naming mechanism).
- [x] 1.8 Assert (do not assume) that `ci-deploy` is in the vector Source-4 allowlist **and** that
      `ci-deploy.sh` sets the matching literal `LOG_TAG` — both directions.

## Phase 2 — R5(a): make the local suite invoke the uncovered runners

- [x] 2.1 Register both runners in `scripts/test-all.sh` via `run_suite`.
- [x] 2.2 Relevance-gate the infra runner; print a loud skip with the exact re-run command.
- [x] 2.3 Add the named `SOLEUR_INCIDENT_SKIP=1` bypass; record the 0.2 wall-clock in the PR body.
- [x] 2.4 Rewrite the `echo`-only mentions and the now-false coverage-boundary comment.
- [x] 2.5 Add `REQUIRED_RUNNERS` to `lint-orphan-test-suites.sh`, anchored on the `run_suite` **call
      shape**, never the bare path.
- [x] 2.6 Mutation-test 2.5 in a sandbox; record the output.

## Phase 3 — R2: reconcile the units whose drop-ins were delivered

- [x] 3.1 **SECURITY PRECONDITION.** Extend `infra-config-install.sh`'s content gate to
      `*.service.d/*.conf` dests with a permitted-directive whitelist; reject `ExecStart=`, `User=`,
      `AmbientCapabilities=`, `NoNewPrivileges=` with named reasons.
- [x] 3.2 Add the `DROPIN_TRY_RESTART` alias **and** its `deploy ALL=(root) NOPASSWD:` User_Spec to
      the sudoers file **and** the `cloud-init.yml` mirror, **and** the `server.tf` `remote-exec`
      grep assertion.
- [x] 3.3 Restructure the script tail: move `sync`/`daemon-reload`/reconcile above the state write;
      add `"restarts":[]` + `"schema_version":2` to the EXIT trap; `rm -f "$STATE_FILE"` at start.
- [x] 3.4 Keep `FILE_MAP` writes **unconditional**; derive `changed` from a `sha256sum` compare used
      only by the predicate; preserve mtime on identical content; `sha256sum` only (never `diff`);
      `lstat`-guard the pre-write read.
- [x] 3.5 Implement the single staleness predicate with `ActiveState` first, activation grading
      (`is-active` + timestamp advance), the `noop_not_active` / `restart_did_not_advance` /
      `sudo_denied` / `unit_inactive` / `timestamp_unparseable` enums, and `vector` last.
- [x] 3.6 Guard every new fallible read with the file's existing idiom + a per-item reason enum.
- [x] 3.7 Emit `SOLEUR_INFRA_CONFIG_RESTART` and the `restarts` array with `active`, `nrestarts`,
      `exec_main_start_ts_before/after`.
- [x] 3.8 Add the staged gate assertion to `adjudicate_infra_config` **only** — warn+pass on
      `schema_version < 2`, fail on malformed / `rc != 0` / `active != active` / the failure enums.
- [x] 3.9 Assert the `depends_on` edge and `triggers_replace` coverage as tasks; fix the two stale
      "18 destinations" comments.
- [x] 3.10 Add the `SYSTEMCTL` test seam and the sudoers↔caller argv lockstep assertion.
- [x] 3.11 Extend `infra-config-apply.test.sh` per the plan's eleven-item list.

## Phase 4 — R3: an absence assertion that cannot pass while the channel is dark

- [x] 4.1 Create `scripts/betterstack-assert-absence.sh` with four outcomes
      (`unknown`/`unshipping`/`present`/`clean` → 3/2/1/0), `unknown` evaluated first.
- [x] 4.2 Read the control in raw-SQL mode with an explicit `host_name` predicate on both the hot and
      archive arms — never via OR-combined `--grep`.
- [x] 4.3 Hoist the canary emit out of the `doppler run` wrapper so the control survives a dead token.
- [x] 4.4 Reject a `--since` shorter than 1 h with a named error.
- [x] 4.5 Add the four positive-control wiring assertions to `journald-config.test.sh`, including that
      the emit site is outside the wrapper.
- [x] 4.6 Repoint the AC12/AC13 discoverability command in the 2026-08-01 plan at the helper.
- [x] 4.7 File the **dedicated soak issue**, cross-link from #7103, add the directive with literal
      secret names and a concrete `earliest`; write the probe with its elapsed-time self-guard,
      ≥3-invocation requirement, and `unshipping`/`unknown` → exit 1.
- [x] 4.8 Write `scripts/betterstack-assert-absence.test.sh` and register it.

## Phase 5 — R4: commit the digest-oracle regression harness

- [x] 5.1 Add the `::add-mask::` of `$b64` **and** `id: rendered_digest` to the workflow step.
- [x] 5.2 Correct (or make true) the step's "no `set -e`" comment — GitHub supplies `bash -e {0}`.
- [x] 5.3 Write `scripts/digest-oracle-guard.test.sh` with an `env -i` hermetic runner, stub-resolution
      assertions, a per-arm `GITHUB_ENV` tempfile, and a `pull_request_target` refusal.
- [x] 5.4 Implement the three residual cases plus the marker-absent, empty-digest, and errexit arms.
- [x] 5.5 Add the `MIN_ASSERTS` floor and the no-interpolation assertion; synthesized fixtures only.
- [x] 5.6 Add the fixture-precondition self-check; register with `run_suite`.
- [ ] 5.7 Record the required-check gating decision verbatim in the PR body.

## Phase 6 — R5(b): prove the liveness gate is non-deletable

- [x] 6.1 Write `scripts/cf-tunnel-liveness-gate-mutations.test.sh` on the sandbox-battery shape.
- [x] 6.2 Implement the seven arms (M1, M3, M4, M5, M6, control, anti-vacuity floor) with per-mutant
      message assertions.
- [x] 6.3 Register with `run_suite`; assert `git status --porcelain` is empty after a run.

## Phase 7 — Records

- [ ] 7.1 Write ADR-155 (provisional ordinal; re-derive at `/ship`).
- [ ] 7.2 Add the one `model.c4` element-description sentence naming the shape gate as the
      delivery↔activation boundary; run the two C4 tests.
- [ ] 7.3 Append the missing Session Error to the 2026-08-01 learning.
- [ ] 7.4 Do **not** touch CHANGELOG.

## Phase 8 — Exit gate

- [ ] 8.1 Run the full local suite on the **final** tree; assert baseline + 4 and that the nested
      runners report 0 RED / RAN ≥ 10. This is also Phase 1's re-verification.
- [ ] 8.2 `shellcheck` every created/edited `.sh`; `actionlint` the two edited workflows (never the
      composite action).
- [ ] 8.3 Assert the AGENTS byte budget is unchanged.
- [ ] 8.4 Resolve every `knowledge-base/` citation in the plan, ADR, and this file.
- [ ] 8.5 Use `Ref #7103` in the PR body — never `Closes`.
