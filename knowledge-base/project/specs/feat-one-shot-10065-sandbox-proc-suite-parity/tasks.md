---
plan: knowledge-base/project/plans/2026-10-12-test-sandbox-masked-proc-suite-parity-plan.md
issue: 10065
branch: feat-one-shot-10065-sandbox-proc-suite-parity
lane: cross-domain
---

# Tasks: sandbox masked-/proc suite parity (#10065)

Ref the plan for rationale. Production writes (merge, deploy dispatch, Doppler) need the operator's go-ahead; this diff performs none.
Run everything in an allocated sandbox (`scripts/soleur-sandbox.sh new|run-isolated|rm`); no full local battery.

## Phase 0 Measurements (gate Phases 4-5 only)

- [x] 0.1 M1 reconcile bwrap prod posture; run `--replay-outer` in the suite image under default masks
- [x] 0.2 M2 run the `buildLikeC4SandboxArgv` argv through `/usr/bin/bwrap` under masks (fd 9 filter, fd 3 status)
- [x] 0.3 M3 (time-boxed, one run) `umount` availability, cover versus drop under retained caps and under the vendor caps
- [x] 0.4 M4 recorder as `SOLEUR_BWRAP_REAL` under the shim; M5 container PATH and `command -v bwrap`
- [x] 0.5 Write `measurements.md` (digest, bwrap version, outcomes, hook-sandbox reachability note); on an M3 identical-behavior result open a security issue and plan the ADR-075 correction

## Phase 1 RED first

- [x] 1.1 `infra/docker-run-tuple.test.sh` battery rows (Guard 1 matrix, H1/H2, must-PASS P1-P3 incl. `if docker run ...; then`) fail on the missing helper
- [x] 1.2 Skeletons: `test/docker-run-tuple-posture.test.ts`, `test/sandbox-vendored-argv-tail.test.ts`, `test/c4-render-argv-fixture.test.ts`

## Phase 2 Tuple helper (P1)

- [x] 2.1 `infra/lib/docker-run-tuple.py` `check` and `posture` (closed-world grammar, census, `UNCLASSIFIED_DOCKER_RUN`, count floor 3)
- [x] 2.2 Battery green against mutated copies in `$WORK`; helper-copy allow-all row proves the battery is not vacuous
- [x] 2.3 `test/docker-run-tuple-posture.test.ts` required-lane wrapper green
- [x] 2.4 Census and grammar hardening from D3 (create/container verbs, per-option `$VAR` allowlist, DUPLICATE_OPTION, attached short forms, placement assertions on rows)

## Phase 3 Suite derivation (P2, P6)

- [x] 3.1 Static `check` before the docker environment checks; `SANDBOX_MASKED_PROC_SRC_ROOT` seam refused under `CI`
- [x] 3.2 `start_container` from `posture --tuple prod`; `-u` from Dockerfile `useradd --uid`
- [x] 3.3 BASE via `runner FROM` one hop (`BASE_LINEAGE`); static and live PATH arms
- [x] 3.4 Raise `MIN_ASSERTIONS` literal (exact; the final value is the one in the suite source, 44 after review round 2)

## Phase 4 Isolation arm (P3, P5; after M3)

- [x] 4.1 `ISO_ARGV` from the canary fixture (`FIXTURE_TAIL` before any docker call)
- [x] 4.2 Recorder arm (`DROP_FAILED`) and `MUTATE=shim-cover` seam
- [x] 4.3 (narrowed by M3: no umount arm, no positive control can exist in the unprivileged image) recorder instrument control and path-normalization rows
- [x] 4.4 Correct the shim header comment (comment lines only) and ADR-075 (Decision clarification and Alternatives row); AC15 comment-only check
- [x] 4.5 `docker inspect` arm on the running suite container (CapAdd, PidMode, User, MaskedPaths, apparmor and seccomp entries)

## Phase 5 Spawn paths (P4; replays per M1/M2)

- [x] 5.1 Outer-wrap `--replay-outer` arm
- [x] 5.2 `infra/c4-render-sandbox-argv.json` + pin test + literal census of bwrap spawn constants and literals
- [x] 5.3 C4 argv docker replay (or measured refusal recorded plus a tracking issue)

## Phase 6 Vendored builder tail (P3)

- [x] 6.1 `test/helpers/vendored-bwrap-tail.ts` extractor (bounded window, chunked scan), per-binary procfs-site counts and `CAP_BARRIER` literal pins (D2, D1)
- [x] 6.2 `test/sandbox-vendored-argv-tail.test.ts` real-binary rows, synthetic mutation rows, `BINARY_MISSING` under `CI`
- [x] 6.3 Live-tail row in `test/sandbox-proc-mask-runtime.test.ts` with cap-segment normalization

## Phase 7 Registrations and CI wiring

- [x] 7.1 `git add` new files, then orphan, guard-vacuity, fixture-relative ratchets
- [x] 7.2 `PROMOTED_FILES`, `FILES_8855` and `PIN_8855`, `apt-bounded` SPECS or EXEMPT only if its census demands
- [x] 7.3 `infra-validation.yml` comment and three `paths:` entries; `test-all.sh --print-selection` check

## Phase 8 Verification (targeted)

- [x] 8.1 Unit battery, `tsc --noEmit`, vitest files by path, docker suite baseline plus every mutation seam red
- [x] 8.2 `guard-vacuity-floor`, `lint-orphan-test-suites`, `fixture-relative-assert`, `apt-bounded`, `grep-q-pipe-guard`, `c4-count-parity`, `lint-guard-contract.py`
- [x] 8.3 Guard Contract row-to-test map recorded here once the tests exist

## Phase 9 Ship

- [ ] 9.1 PR body `Closes #10065`; AppArmor-profile result claimed only after CI shows it
- [ ] 9.2 Operator go-ahead, then `gh pr merge 10110 --auto` (no `--squash`); one re-arm on a dequeue, then stop and report

## Outcomes and Guard Contract row-to-test map (AC11)

- 4.3 narrowed by M3: no behavioral cover-vs-drop or umount arm (every umount2 is EPERM, no positive control exists in the unprivileged image); the recorder arm is the discriminator. 4.4 shipped as the ADR-075 addendum and the shim header comment correction.
- 5.1 = branch (b): outer-wrap replay cannot run (`wrong_elevation_userns`, M1); tracked in #10115. 5.2/5.3 = branch (a): static pins plus the C4 replay run under the masks.
- 7.4 apt-bounded: no SPECS edit needed (the derived container reuses `start_container`; the guard now sits before the apt budget lines). 7.6 (required-lane wrapper) = `test/docker-run-tuple-posture.test.ts`.
- Guard 1 rows 1-11, H1/H2, P1-P10: `apps/web-platform/infra/docker-run-tuple.test.sh` (176 rows after review round 2; `MIN_ROWS` is exact) and the suite's static call; row 5-6-11 count floor of exactly 3 in `docker-run-tuple.py`.
- Guard 2 rows 1 (`MUTATE=shim-cover`, red via DROP_FAILED only), 6 (fixture rows, static battery), 7 (`shim-bypass`), recorder instrument control and analyzer path-normalization rows (in the suite, 21 analyzer rows); rows 2-5, 9-11 (tail drift, anchors, binary missing, procfs site counts, cap barrier): `test/sandbox-vendored-argv-tail.test.ts` and `test/sandbox-proc-mask-runtime.test.ts`. Row 8 (arm deletion) is carried by the exact `MIN_ASSERTIONS=34` literal.
- Guard 3: `test/c4-render-argv-fixture.test.ts` (fixture pin, constants, literal census, no-procfs assertion) plus the suite's C4 replay arm.
- Guard 4 rows 1-5 and the PATH forms (legacy, multi-var, `/usr/bin` first, compliant, stage-name case, last USER): suite static arms, verified by the static arms through `test/docker-run-tuple-posture.test.ts` (the counts are read from the suite source); live PATH arm and `MUTATE=shim-path`.
- Local verification (2026-10-12, `SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined`): suite 34 passed 0 failed at the first run (superseded by the line below); seams `shim-splice`, `shim-bypass`, `shim-cover`, `shim-path`, `control-unmasked`, `sleeper-after`, `no-replay` each red on their own diagnostic; static battery 16/16 (red rows made zero docker calls). The AppArmor-profile half is proven only by CI.

## Review round (2026-10-12, 13 seats, panel SHA 74b5c3de9c)

Fixed inline (all in this PR): outer-wrap argv no-`--proc` assertion (was unpinned); census escapes (chained second statement after an exempt site, `<<` arithmetic/quoted heredoc blinding, `)` case-label position, uppercase `$DOCKER` indirect wrapper, symlink/unbounded read, privilege-class options on exempt sites, `--memory 0`); drop analyzer (`..` normalization, ordering vs the root bind, symlink/file dest, `--args` unmodeled); docker-suite static arms now also run in the REQUIRED lane (vitest wrapper with a failing `docker` stub, 9 mutated-copy rows) and the posture digest is pinned there; `ELEVATION` arm; `MUTATION_UNKNOWN`; exact `MIN_ASSERTIONS` (39); `CONTAINER_START_FAILED`; unbound-variable abort; in-image fixture regeneration command and remediation text; removal-direction rows; memoized binary scans; lockfile variants pinned to one version; live-tail spawns selected by shape; shared comment stripper; bind-table parity row; consumer floor 7; ADR-075 addendum (observed vs inferred, unelevated-bwrap condition, supersession pointer); stale comments.
Tracked, not fixed (CONCUR from code-simplicity-reviewer): residual gaps in #10115 (SOLEUR_BWRAP_* hijack-list names, outer-wrap replay, runner-image fidelity, census scope), trigger = dependency on #10063.
Local verification after round 1 fixes: docker suite 39/0 (unconfined override), tuple battery 137/137, vitest 7 files green incl. `CI=1`.

## Review round 2 (fix-commit targeted round, 7 report-only seats)

Fixed inline: exempt sites parsed closed-world (create is exactly `--name NAME IMAGE`, the cosign run is its exact option set) instead of a denylist, and exempt lines no longer shield the indirect and name scans; `<<` inside `${ }`, `$[ ]`, `$'...'`, `[[ ]]` is refused as ambiguous; unreadable, symlinked or oversize wide-scope files are violations; case-insensitive `$DOCKER` variable, `setsid` wrapper, `(label)` case form; analyzer treats relative, empty and fd root binds as root binds; ELEVATION widened (symbolic and octal modes, `--chmod=`, `install -m`, `dpkg-statoverride`) plus a live `stat` arm, worded as best-effort; the capability attribution is hedged as inferred (suite header, shim header, measurements M1/M3, ADR-075 with a third condition and an inline pointer at the Isolation effect paragraph); the posture wrapper derives the digest and reads exact arm counts from the suite source; the #10115 probe is now an event-grep on main's `ci-deploy.sh`.
Local verification after round 2: docker suite 44/0 (unconfined override), all 7 seams red on their own diagnostics (`shim-splice` mount proc refused, `shim-bypass` VISIBLE and DROP_FAILED, `shim-cover` DROP_FAILED only, `shim-path` PATH_ORDER, `control-unmasked` control not refused, `sleeper-after` no sibling, `no-replay` non-vacuity), tuple battery 176/176, 5 vitest files 112/112 (and the posture and vendored-tail files green under `CI=1`), `tsc --noEmit` clean, shellcheck clean at warning level for the changed suites, guard-vacuity, grep-q-pipe-guard, orphan lint, mutation-scorer consumers, apt-bounded, fixture-relative (62/62), lint-guard-contract all green. The #10115 probe was driven offline with a stub `gh` across the three states (open, closed, anchor moved).
