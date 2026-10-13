# Tasks: agent sandbox shim — fresh procfs mount fails under docker's masked /proc (H6)

Plan: knowledge-base/project/plans/2026-10-11-fix-sandbox-shim-procfs-under-masked-proc-plan.md
Issues: #10032 (closes; AC4 satisfies #9860's close condition), #10045 (deferred kernel-stream grant)

## Phase 0: measurement spike (gate for the fix shape)

- [x] 0.1 Capture the real multicall fd surface: run the SDK spawn path (capture harness or a one-off in-image probe) and record each `/proc/self/fd/<N>` occurrence — SUBSTRING scan over the whole serialized argv (a ref embedded inside a `bash -c '…'` string counts) — with each fd's type: real path vs `memfd:` vs O_PATH — via `readlink /proc/self/fd/<N>` + `/proc/self/fdinfo/<N>` at shim time. Selects the re-home rung.
- [x] 0.2 Build the rewritten argv through the REAL shim (`SOLEUR_BWRAP_REAL=<recorder stub>`) over the committed `infra/sandbox-canary-argv.json` fixture AND an `--args`-payload-shaped input; record the realized merged stream. Measure the real shim, never a hand-shaped fixture.
- [x] 0.3 In-image verify on the prod posture: `docker run` the current image under prod security opts (apparmor=soleur-bwrap, repo seccomp, DEFAULT masked `/proc`) and exec the rewritten argv on the image's bubblewrap 0.8.0 (apt `bubblewrap` in `apps/web-platform/Dockerfile` — NOT the dev host's 0.12): assert rc=0, multicall exec resolves, `ls /proc` shows no pid dirs, host pid absent. Extend `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` or add a sibling harness — reuse, do not duplicate.
- [x] 0.4 Enumerate in-sandbox `/proc` pseudo-file dependencies beyond `/proc/self/fd/N` (agent-payload reads: `ps`, `/proc/meminfo`, `/proc/cpuinfo`): classify each as hard-break vs cosmetic-degrade; record the acceptance decision.
- [x] 0.5 Decision gate: GO (procfs-free realization) / FALLBACK (`systempaths=unconfined`, review-gated) / ESCALATE to #9773 acceleration — a third outcome is a plan amendment, not a silent pivot. Commit the record to `knowledge-base/project/specs/feat-one-shot-10032-sandbox-shim-procfs/measurements.md`.

## Phase 1: shim rewrite (RED → GREEN)

- [x] 1.1 RED(unit): `apps/web-platform/test/bwrap-shim.test.ts` cases for each rewrite arm — tail bind dropped from outer argv AND from inside an `--args` payload; `--proc` never emitted; fd re-home emitted per `/proc/self/fd/N` ref (0, 1, ≥2 — count asserted, second-member row); unreadable/O_PATH-only fd → refuse; unknown exposure form → refuse; non-exposed argv passes through unchanged. Run to confirm RED.
- [x] 1.2 GREEN: rewrite `apps/web-platform/infra/bwrap-shim/bwrap` — exposure scan feeds a neutralize path (drop procfs-mount-at-/proc tokens, emit re-home mounts at the last setup position of the merged stream) replacing the `--proc` splice; payload re-emit becomes selective; `setup_marks` keeps merged-stream semantics; keep the `bwrap-shim:` fail-closed contract; restate whether the rewritten parser inherits the `--opt=` equals-form known limit.
- [x] 1.3 Update `apps/web-platform/server/agent-runner-sandbox-config.ts` comments (the #9723 block ~L498-506 + `enableWeakerNestedSandbox` ~L35-41/~L570-575) to the tmpfs + re-home realization — comments only, `denyRead "/proc"` stays. Re-run `npx vitest run test/sandbox-credential-deny-runtime.test.ts` — the ADR-272 re-measure mandate on any sandbox-flag change.

## Phase 2: canary re-spec

- [x] 2.1 Re-spec the `proc_mask` hardening probe in `apps/web-platform/scripts/sandbox-canary.mjs` (~L432-442): replace the `/proc/self/environ` assertion (false-by-design under tmpfs) with "no `/proc/<pid>` directory entries visible"; `classifyProcMaskProbe` keeps the `proc_mask_defeated` / `canary_infra_error` split.
- [x] 2.2 Update `apps/web-platform/test/sandbox-canary.test.ts`, `apps/web-platform/test/sandbox-proc-mask-runtime.test.ts`, `apps/web-platform/test/sandbox-isolation.test.ts` — keep a mutation that restores the tail bind driving `proc_mask_defeated` (probe must stay drivable red).
- [x] 2.3 `apps/web-platform/scripts/sandbox-canary-regression.test.sh` §D4 parity: `BWRAP_FD_VALUED_OPTS` unchanged (`--bind-data`/`--perms` already in the vocabulary) — assert green; add census rows only if the option table moves.

## Phase 3: deploy-observability, records, review

- [x] 3.1 ADR-075 addendum `## Addendum — 2026-10-11 (#10032)` in `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`: mechanism change (pidns-scoped fresh procfs → vendored `--tmpfs /proc` + fd re-home); `systempaths=unconfined` dispositioned (re-rejected with scope named, or accepted under the fallback arm with the unmasked path set enumerated); #9773 remains the end-state.
- [x] 3.2 `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: mark H6 resolved-by (#10032); update `sdk_probe`/`sdk_noproc` row readings; disposition the `SOLEUR-DEBT` kdeny note.
- [x] 3.3 `apps/web-platform/infra/ci-deploy.sh` comment/row refresh only if the diag script's interpretation changed (rows stay — diagnostics). Fallback arm ONLY: `--security-opt systempaths=unconfined` at the two `docker run` sites.
- [x] 3.4 `knowledge-base/legal/compliance-posture.md`: register note in honest tense — the Art. 32 TOM's mechanism changed; no new processing activity.
- [ ] 3.5 CTO + CLO review seats at `soleur:review` (issue mandate); CPO sign-off per `requires_cpo_signoff` (operator-attested in PR body).
- [x] 3.6 `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` +1 with PLACEMENT/TRUTH/NO-SUBSTITUTE comment (the plan's `credentials_required` declaration moves the ratchet; same PR — no file-scoped suite reaches it).

## Phase 4: verification

- [x] 4.1 `npx vitest run test/bwrap-shim.test.ts test/sandbox-canary.test.ts test/sandbox-proc-mask-runtime.test.ts test/sandbox-isolation.test.ts test/agent-runner-sandbox-config.test.ts` — green; `bash apps/web-platform/scripts/sandbox-canary-regression.test.sh` green.
- [x] 4.2 Run each literal AC command once: `git grep -nE 'security-opt[= ]+systempaths' apps/web-platform/` (expect zero under chosen arm); in-image verify harness output captured.
- [x] 4.3 `npx markdownlint-cli2` on new/edited markdown — green.
- [ ] 4.4 Final AC sweep (AC1-AC9 pre-merge); PR body: `Closes #10032` on its own line, CPO-signoff attestation line, CTO+CLO review record pointers, note "post-merge AC4 verified via deploy-state + `doppler run -c prd -- scripts/betterstack-query.sh`".
- [ ] 4.5 Post-merge: first prod deploy — faithful canary verdict `pass` read from deploy-state (`/mnt/data/ci-deploy-sandbox-canary.json` via the existing no-SSH read channel); zero `SOLEUR_CANARY_SANDBOX_DIAG` rows; comment on #9860 that its close condition is met.
