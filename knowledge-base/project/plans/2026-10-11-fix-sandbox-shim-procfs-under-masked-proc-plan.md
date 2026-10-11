---
title: "fix: agent sandbox shim — fresh procfs mount fails under docker's masked /proc (H6)"
type: fix
date: 2026-10-11
slug: fix-sandbox-shim-procfs-under-masked-proc
branch: feat-one-shot-10032-sandbox-shim-procfs
issue: 10032
closes: 10032
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: agent sandbox shim — fresh procfs mount fails under docker's masked /proc (H6)

## Overview

The production faithful sandbox canary has reported `sandbox_broken` /
`bwrap_operation_not_permitted` on every deploy since 2026-10-09T04:52Z
(#9860, open). The diagnostic rows shipped by PR #9938 name H6 PROBABLE:
the bwrap PATH shim's tail `--proc /proc` splice (the #9723 cross-tenant
mask, realized at spawn) cannot mount a fresh procfs inside a user
namespace while Docker's default masked `/proc` is in force — `sdk_probe`
returns EPERM while `sdk_noproc` (the same argv minus `--proc /proc`)
returns rc=0. This plan fixes the agent sandbox spawn so it builds under
the masked `/proc` without re-opening the #9723 cross-tenant
`/proc/<pid>/environ` exposure, records the decision as an ADR-075
addendum, and restores the faithful canary to green.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement / Motivation

Every Agent SDK sandboxed Bash spawn fails closed in production: the
vendored builder's argv ends with `--bind /proc /proc` (the
`enableWeakerNestedSandbox` tail), the shim splices `--proc /proc` over it
to keep the #9723 mask honest, and `mount(2)` of that fresh procfs is
refused by the kernel's `mount_too_revealing` check because the
container's `/proc` carries Docker's masked sub-mounts (bubblewrap#284;
the ADR-075 2026-10-08 addendum already measured the identical EPERM for
the outer-wrap arm). The SDK availability check (`bwrap --version`)
passes through the shim untouched, so the app reports healthy while every
sandbox spawn errors — a fail-closed outage with weak per-user
attribution. Presumed tenant-impacting per the runbook until a live read
shows otherwise.

## Proposed Solution

**Chosen shape — shim argv rewrite ("procfs-free realization"), merging
the issue's candidate fixes 2 and 3:** the /proc mask stops depending on
mounting a fresh procfs entirely.

When the merged setup stream's only `/proc` exposure is the vendored tail
`--bind /proc /proc`, `infra/bwrap-shim/bwrap` will:

1. **Drop the tail bind** from the re-emitted stream (payload re-emit
   becomes selective rather than verbatim — a normalized-dest `/proc`
   procfs mount inside an `--args` payload or the outer argv is removed,
   never passed through). The config's `denyRead: "/proc" → --tmpfs /proc`
   then lands as the REALIZED mask — an empty, mountless `/proc`, stronger
   than today's pidns-scoped procfs and impossible under no container
   posture.
2. **Never splice `--proc /proc`.** The splice arms (A/B/C) are replaced
   by the fd re-home emitter below.
3. **Re-home every command-side `/proc/self/fd/N` reference** — the one
   /proc path the vendored inner command needs (its apply-seccomp
   multicall execs `/proc/self/fd/N`). The shim already enumerates these
   tokens via `add_cmd_fd_refs`; for each it emits a setup mount at the
   literal path `/proc/self/fd/<N>` (token-preserving — no command-token
   rewrite), realized by the first rung of this ladder that the fd
   supports:
   - `--ro-bind <resolved-source> /proc/self/fd/<N>` when
     `readlink /proc/self/fd/<N>` resolves a real, readable file path
     (e.g. the vendored CLI binary on disk);
   - `--perms 0755 --bind-data <N> /proc/self/fd/<N>` when the fd is a
     readable regular file or memfd (both options exist in prod's
     bubblewrap 0.8.0 — verified against bwrap NEWS/man; `--bind-fd`,
     the cleaner O_PATH bind, is ≥0.10.0 and is NOT available);
   - otherwise **refuse** (exit 65, `bwrap-shim:` marker) — never a
     silently-broken multicall.
4. **Keep fail-closed.** A proc-exposing argv that cannot be neutralized
   (unreadable fd, non-bindable source, an exposure form the rewriter
   does not recognize) refuses the spawn — same contract as today.

**Review-gated fallback — `systempaths=unconfined` (issue candidate 1):**
if the Phase-0 spike measures that the rewrite cannot preserve P2+P3
(multicall fd unbindable AND unreadable, or a measured in-sandbox /proc
dependency the ladder cannot satisfy), the contingency is
`--security-opt systempaths=unconfined` at the two `docker run` call
sites in `apps/web-platform/infra/ci-deploy.sh` (~L4250 canary,
~L4595 prod). It unmasks a fixed list (`/proc/{kcore,keys,sched_debug,
latency_stats,timer_list,timer_stats,asound,acpi,scsi}`,
`/sys/{firmware,devices/virtual/powercap}`) for the WHOLE shared
container — the widening ADR-075's addendum already names "a widening,
not a fix" — so it ships only with the widening scope enumerated in the
ADR-075 addendum and recorded in the CTO+CLO review this issue mandates.

**Not the strategy:** the per-tenant executor topology (#9773, epic
#9842, operator-approved) subsumes this whole surface; this fix is the
interim availability restore, deliberately confined to the shim+canary.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
|---|---|---|
| "`sdk_noproc` … the SAME argv minus `--proc /proc`" | The DIAG `sdk_noproc` is a *hand-written minimal* argv (`--unshare-user --unshare-pid --dev /dev --bind / /`), not the vendored argv minus the splice — the real vendored argv also carries the tail `--bind /proc /proc`, `--args` payloads, denyRead tmpfs, seccomp fd options (`ci-deploy.sh` ~L1674 vs `infra/sandbox-canary-argv.json` tail) | rc=0 isolates the mount failure only; it is NOT evidence that a procfs-free *production* argv preserves the mask — the plan treats the tail-bind drop + fd re-home as the real work |
| "A procfs-free shim argv path — `sdk_noproc rc=0` is the first measurement that this class works on the real host" | Procfs-free-as-"delete the splice" re-exposes the container procfs via the tail bind → #9723 regression in *worse* form (shared container pidns incl. the server process env) | Cut in Phase 0.6b; only the merged fix-2/3 shape is planned |
| "Candidate fix 2: a procfs mask that does not require mounting a fresh procfs under a masked parent" | Exists implicitly: `denyRead "/proc"` already projects `--tmpfs /proc` — the only reason it is intent-not-realized is the tail bind mounting over it | Candidate 2 is realized by removing the tail bind; no new mask mechanism is invented |
| `enableWeakerNestedSandbox` "skips `--proc /proc` in bwrap" | True for the vendor's own `--proc`, but the builder still appends the tail `--bind /proc /proc` — the shim's own comment and the fixture pin this | Fix lives in the shim (the layer we control), not the SDK config |

## Implementation Phases

### Phase 0 — Measurement spike (gate for the fix shape)

Deliverable: a measurement record committed to
`knowledge-base/project/specs/feat-one-shot-10032-sandbox-shim-procfs/measurements.md`.

- [ ] 0.1 Capture the real multicall fd surface: run the SDK spawn path
  (capture harness or a one-off in-image probe) and enumerate EVERY
  `/proc/self/fd/<N>` occurrence by SUBSTRING scan over the whole
  serialized argv — a ref embedded inside a `bash -c '…'` string counts
  as much as a standalone token — recording each fd's type (real path
  vs `memfd:` vs O_PATH) via `readlink /proc/self/fd/<N>` +
  `/proc/self/fdinfo/<N>` at shim time. This selects the re-home rung.
- [ ] 0.2 Build the rewritten argv through the REAL shim
  (`SOLEUR_BWRAP_REAL=<recorder stub>`) over the committed fixture argv
  AND an `--args`-payload-shaped input; record the realized merged stream.
  Per `2026-07-27-my-refutation-measured-a-shim-...`, measurement must
  run the real shim, never a hand-shaped fixture.
- [ ] 0.3 In-image verify on the prod posture: `docker run` the current
  image under the prod security opts (apparmor=soleur-bwrap, repo seccomp,
  DEFAULT masked `/proc`) and exec the rewritten argv on the image's
  bubblewrap (**0.8.0** — apt `bubblewrap` in `apps/web-platform/Dockerfile`,
  not the dev host's 0.12): assert rc=0, multicall exec resolves,
  `ls /proc` shows no pid dirs, host pid absent. Extend
  `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` or add a
  sibling harness — reuse, do not duplicate.
- [ ] 0.4 Enumerate in-sandbox `/proc` pseudo-file dependencies beyond
  `/proc/self/fd/N` (agent-payload reads such as `ps`, `/proc/meminfo` —
  heap sizing — `/proc/cpuinfo`): classify each as hard-break vs
  cosmetic-degrade; record the acceptance decision.
- [ ] 0.5 Decision gate: GO (procfs-free realization) / FALLBACK
  (`systempaths=unconfined`, review-gated per Proposed Solution) /
  ESCALATE to #9773 acceleration (record why — a third outcome is a
  plan amendment, not a silent pivot).

### Phase 1 — Shim rewrite (RED → GREEN)

- [ ] 1.1 Failing tests first (`cq-write-failing-tests-before`):
  `apps/web-platform/test/bwrap-shim.test.ts` cases for each rewrite arm —
  tail bind dropped from outer argv AND from inside an `--args` payload;
  `--proc` never emitted; fd re-home emitted per `/proc/self/fd/N` ref
  (0, 1, and ≥2 refs — the second-member case); unreadable/O_PATH-only fd
  → refuse; unknown exposure form → refuse; non-exposed argv passes
  through unchanged.
- [ ] 1.2 Rewrite `infra/bwrap-shim/bwrap`: exposure scan now feeds a
  *neutralize* path (drop procfs-mount-at-/proc tokens, emit re-home
  mounts at the last setup position of the merged stream) instead of the
  `--proc` splice; payload re-emit becomes selective; `setup_marks` keeps
  the merged-stream semantics; keep the `bwrap-shim:` fail-closed contract
  and the `--opt=` equals-form known-limit comment honest (re-state
  whether the new parser inherits it).
- [ ] 1.3 Update `apps/web-platform/server/agent-runner-sandbox-config.ts`
  comments (the #9723 block ~L498-506 describes the realized mask as the
  shim's `--proc` splice — now the tmpfs + re-home realization) and the
  `enableWeakerNestedSandbox` comment ~L35-41 / ~L570-575. Re-run
  `sandbox-credential-deny-runtime.test.ts` — the ADR-272 re-measure the
  header mandates on any sandbox-flag change.

### Phase 2 — Canary re-spec

- [ ] 2.1 Re-spec the `proc_mask` hardening probe in
  `apps/web-platform/scripts/sandbox-canary.mjs` (~L432-442): the
  `/proc/self/environ` half dies under a tmpfs mask by design; the
  realized-mask assertion becomes "no `/proc/<pid>` directory entries
  visible" (covers host-pid, sibling-pid, and any real procfs) while the
  multicall-success half is witnessed by the replay's own rc=0.
  `classifyProcMaskProbe` keeps the `proc_mask_defeated` /
  `canary_infra_error` split on the same discrimination rules.
- [ ] 2.2 Update `apps/web-platform/test/sandbox-canary.test.ts`,
  `apps/web-platform/test/sandbox-proc-mask-runtime.test.ts`, and
  `apps/web-platform/test/sandbox-isolation.test.ts` to the new
  realization; keep a mutation that restores the tail bind driving
  `proc_mask_defeated` (the probe must still be drivable red — learning
  `2026-07-19-...the-canary-could-not-fail`).
- [ ] 2.3 `apps/web-platform/scripts/sandbox-canary-regression.test.sh`
  §D4 parity: `BWRAP_FD_VALUED_OPTS` and the shim's fd tables are
  unchanged (`--bind-data`/`--perms` were already in the vocabulary) —
  assert it stays green; add census rows only if the option table moves.

### Phase 3 — Deploy-observability, records, review

- [ ] 3.1 ADR-075 addendum `## Addendum — 2026-10-11 (#10032)`: mechanism
  change — realized mask moves from pidns-scoped fresh procfs to
  tmpfs + fd re-home under docker's masked `/proc`; `systempaths=unconfined`
  re-rejected with the widening scope named (or, if the fallback shipped,
  the acceptance recorded); #9773 remains the end-state; the #9723 mask
  is preserved in effect, not in mechanism.
- [ ] 3.2 Runbook `canary-probe-set.md`: mark H6 resolved-by (this plan),
  update `sdk_probe`/`sdk_noproc` row readings for the post-fix world,
  disposition the `SOLEUR-DEBT` kdeny note.
- [ ] 3.3 `ci-deploy.sh` comment/row refresh only if the diag script's
  interpretation changed (the rows stay — they are diagnostics).
- [ ] 3.4 `knowledge-base/legal/compliance-posture.md`: register note in
  honest tense — the Art. 32 TOM's mechanism changed (same 2026-10-09
  row pattern), no new processing activity.
- [ ] 3.5 CTO + CLO review seats at `soleur:review` (issue mandate);
  CPO sign-off posture per `requires_cpo_signoff` (operator-attested in
  PR body, per the established pattern).
- [ ] 3.6 The `discoverability_test.credentials_required` declaration
  above moves the repo-global ratchet: bump `BASELINE_DECLARED_PROBES`
  in `plugins/soleur/test/preflight-discoverability-test.test.ts` with
  the PLACEMENT/TRUTH/NO-SUBSTITUTE comment its failure text requires —
  same PR, no file-scoped suite reaches it (sharp-edge #8651/#7393 G1).

### Phase 4 — Deploy verification

- [ ] 4.1 First prod deploy carrying the fix: faithful canary verdict
  `pass`; `SOLEUR_CANARY_SANDBOX_DIAG` bundle does not fire (it arms only
  on `sandbox_broken`); #9860 close condition met.
- [ ] 4.2 Kernel-stream grant (P7): stays deferred — tracking issue
  filed by this plan (see Deferred / Follow-up); `kdeny src=none`
  remains the documented expected state until that separate host-IaC
  plan exists.

## Files to Edit

- `apps/web-platform/infra/bwrap-shim/bwrap` — the rewrite (exposure
  neutralize + fd re-home; `--proc` splice removed).
- `apps/web-platform/server/agent-runner-sandbox-config.ts` — comment
  re-truthing only (no behavioral change expected; the denyRead `/proc`
  entry stays — it IS the realized mask now).
- `apps/web-platform/scripts/sandbox-canary.mjs` — `proc_mask` probe
  re-spec + classifier comments.
- `apps/web-platform/test/bwrap-shim.test.ts` — new rewrite-arm pins;
  update the cases that pin the `--proc` splice.
- `apps/web-platform/test/sandbox-canary.test.ts` — probe/classifier
  updates.
- `apps/web-platform/test/sandbox-proc-mask-runtime.test.ts` — realized
  mask assertions for the tmpfs shape.
- `apps/web-platform/test/sandbox-isolation.test.ts` — tail-bind/proc
  cases updated to the rewritten argv.
- `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts` —
  re-run + re-pin if the measurement moves (ADR-272 mandate).
- `apps/web-platform/scripts/sandbox-canary-regression.test.sh` — only if
  the fd-valued option table moves (expected: stays green, assert so).
- `apps/web-platform/infra/ci-deploy.sh` — comment refresh only under
  the chosen path; `--security-opt systempaths=unconfined` at the two
  `docker run` sites ONLY under the fallback arm.
- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — extend
  for the rewritten-argv in-image verify (or document reuse).
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` — addendum.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` —
  H6 row resolution.
- `knowledge-base/legal/compliance-posture.md` — register note.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` —
  `BASELINE_DECLARED_PROBES` +1 with PLACEMENT/TRUTH/NO-SUBSTITUTE
  comment (Phase 3.6).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10032-sandbox-shim-procfs/measurements.md` — Phase-0 measurement record (the spike deliverable).
- Possibly one focused shell probe under `apps/web-platform/infra/` for
  the in-image rewritten-argv verify, only if the existing harness
  cannot carry it (decided at 0.3).

## User-Brand Impact

- **If this lands broken, the user experiences:** every agent Bash
  sandbox spawn errors while the app reports healthy — the agent's shell
  capability fails closed on the customer's workspace session (the
  current prod state this plan exists to end; a botched fix keeps it).
- **If this leaks, the user's data is exposed via:** a weakened or absent
  `/proc` mask letting one tenant's sandboxed command read another
  process's `/proc/<pid>/environ` (and `cwd`/`root`/`ns`/`fd`) inside the
  shared container pidns — the server process's environ carries platform
  secrets, so the blast radius exceeds a single sibling workspace.
- **Brand-survival threshold:** `single-user incident` (carried forward
  from the 2026-10-08 tenant-fs-isolation brainstorm — same boundary,
  same vector).
- **Threshold decision (challengeable):** a realized breach is one
  tenant's data read by another tenant's agent — a discrete
  confidentiality incident, not an aggregate pattern; the threshold is
  about the *violation* materializing, while the fix itself fails closed.

`requires_cpo_signoff: true` — `soleur:engineering:review:user-impact-reviewer`
runs at review time per the review skill's conditional-agent block; CPO
sign-off is operator-attested in the PR body (established pattern).
CLO-scope advisory (gdpr-gate Phase 2.7, run inline): the `/proc` mask is
an Art. 32 confidentiality TOM — mechanism change recorded in
`compliance-posture.md` in honest tense; `/proc` reads leave no audit
trail, so the canary `proc_mask` probe remains the only breach-witness —
it must stay discriminating (Art. 33 adjacency). No Art. 9/6/17/Chapter-V
findings (no schema, auth, API, or vendor-data surfaces touched).

## Observability

```yaml
liveness_signal:
  what: faithful sandbox canary verdict (pass | sandbox_broken | canary_infra_error) written to deploy-state /mnt/data/ci-deploy-sandbox-canary.json + Sentry page on sandbox_broken
  cadence: every prod deploy (deploy-pipeline arm, report-only non-blocking)
  alert_target: Sentry issue → email (sandbox-canary op event)
  configured_in: apps/web-platform/infra/ci-deploy.sh run_faithful_sandbox_canary (~L2903) + sandbox_canary_sentry_event (~L743)
error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (sandbox-canary event) + journald tag ci-deploy → Better Stack
  fail_loud: SOLEUR_CANARY_SANDBOX_DIAG journald bundle (fires only on sandbox_broken) + Sentry "sandbox canary sandbox_broken" event
failure_modes:
  - mode: rewritten shim regresses the mask or the multicall re-home
    detection: IN-SURFACE — the faithful canary's proc_mask probe runs the payload inside the replayed sandbox and asserts no /proc/<pid> dirs; a defeated mask reports proc_mask_defeated (sandbox_broken), a spawn-side failure reports the probe's exit/spawn class
    alert_route: Sentry sandbox-canary event → email
  - mode: shim refuse (exit 65, bwrap-shim:) on a real argv shape
    detection: IN-SURFACE — classifyShared maps bwrap-shim: stderr to sandbox_broken/bwrap_shim_refused; runtime path: agent-runner sandbox-startup Sentry mirror (feature: agent-sandbox) on the error signature
    alert_route: Sentry → email
  - mode: spawn works but an in-sandbox /proc dependency degrades (e.g. ps/meminfo reads on empty tmpfs)
    detection: deploy-time none by design (accepted cosmetic degradation per Phase 0.4); runtime witness is the session error signature reaching Sentry via the agent-runner mirror
    alert_route: Sentry issue stream (no dedicated alert — degradation is cosmetic)
logs:
  where: journald CONTAINER_NAME=soleur-web-platform + tag ci-deploy → Better Stack source; SOLEUR_CANARY_SANDBOX_DIAG rows on failure
  retention: Better Stack plan retention
discoverability_test:
  command: printf 'ok'
  expected_output: ok
  credentials_required: "deploy-state (/mnt/data/ci-deploy-sandbox-canary.json on the prod host) + Sentry org read — the faithful-canary verdict is a deployed signal with no unauthenticated local substitute; the local stand-ins (unit tests, shim self-test) verify code, not the deployed observability state"
```

## Architecture Decision (ADR/C4)

### ADR

- Amend `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`
  — new addendum `## Addendum — 2026-10-11 (#10032)`: the realized `/proc`
  mask mechanism moves from the shim's pidns-scoped fresh-procfs splice to
  the vendored `--tmpfs /proc` + fd re-home under docker's masked `/proc`;
  `systempaths=unconfined` dispositioned (re-rejected with scope named, or
  accepted under the fallback arm — the addendum records whichever the
  Phase-0 gate selects); #9773 remains the recorded end-state. In-scope
  task: Phase 3.1 — a deliverable of THIS plan, not a follow-up.

### C4 views

- **No C4 impact — checked against all three model files**
  (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,
  spec.c4}`, all read): (a) external human actors — none new or changed
  (tenant agent sessions unchanged as actors); (b) external systems /
  vendors — none new (the change is argv shaping inside the existing
  webapp container); (c) containers/data stores — none new (the shim is a
  file inside the existing container image; model.c4 carries no
  shim-level element and the agent-sandbox boundary is documented at ADR
  granularity, below the model's); (d) actor↔surface relationships —
  unchanged. Run `apps/web-platform/test/c4-code-syntax.test.ts` +
  `c4-render.test.ts` as regression only.

### Sequencing

- The addendum is authored in this PR describing the shipped state; if
  the fallback arm ships, the addendum states the accepted widening and
  its re-evaluation trigger (#9773 GA) rather than a silent deferral.

## Guard Contract

### Guard 1 — shim realized-mask rewrite pin (`test/bwrap-shim.test.ts`)

**Property.** The merged setup stream the shim re-emits never mounts
procfs at `/proc` (no `--proc`, no bind-family token with normalized
dest `/proc`), and every command-side `/proc/self/fd/N` reference in the
merged stream has a corresponding setup re-home mount at the literal
dest `/proc/self/fd/N`.

**Assembly.** The shim's one merged-stream rewrite path
(`infra/bwrap-shim/bwrap` stage-1 consume → stage-2 emit): the outer
argv AND every consumed `--args` payload pass through the same
`setup_marks` scan + re-emit; the test exercises the shim binary against
the committed fixture argv plus synthesized payload shapes — the single
chokepoint all spawn argv flows through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the `--proc /proc` splice as the mask emitter | RED |
| 2 | Emit zero re-home mounts while preserving a `/proc/self/fd/N` command ref (guard's own dispatch: suite must assert the re-home COUNT, not just absence of `--proc`) | RED |
| 3 | Add a second `/proc/self/fd/M` command ref after a compliant first — only the first re-homed | RED |
| 4 | Move the tail `--bind /proc /proc` from the outer argv into a second `--args` payload — exposure must still be neutralized | RED |
| 5 | Suite-side: delete the count assertion so "0 re-homes" also passes — vacuous harness row | RED (the row exists to pin the assertion) |
| 6 | must-PASS: an argv with no /proc exposure and no `/proc/self/fd` refs passes through unmodified | PASS |

**Anchor.** Assertions are behavioral over the shim binary + the
committed `infra/sandbox-canary-argv.json` fixture; weakening both the
fixture and the shim requires the same edit to also defeat the
`--verify` capture gate (CI re-capture byte-diff on the real SDK), which
is outside this PR's diff.

### Guard 2 — canary `proc_mask` probe discrimination (`sandbox-canary.mjs` + `test/sandbox-canary.test.ts`)

**Property.** The deploy-time `proc_mask` probe reports
`proc_mask_defeated` (sandbox_broken) exactly when any real procfs
content is visible in-sandbox, and never for the legitimately-empty
tmpfs mask.

**Assembly.** The probe argv + `classifyProcMaskProbe` +
`runHardeningProbes` in `apps/web-platform/scripts/sandbox-canary.mjs` —
the single replay path ci-deploy invokes; the unit suite replays the
classifier against payload fixtures.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the vendor tail bind in the replayed argv (host pid dirs visible) | proc_mask_defeated |
| 2 | Probe argv asserts only "spawn rc=0" — mask defeated but spawn clean (guard's own dispatch accepts anything) | RED |
| 3 | Add a second pid-dir assertion so the probe only checks the canary's own host pid — a sibling pid dir visible but host pid absent must still defeat | RED |
| 4 | Suite-side: remove the mask-defeated fixture so `classifyProcMaskProbe` is only exercised on pass inputs | RED (vacuous harness) |
| 5 | must-PASS: tmpfs /proc with only the re-home fd mounts — probe passes (the new legitimate shape) | PASS |

**Anchor.** The probe's red class is verified by replaying the fixture
argv, which CI byte-diffs against a real-SDK capture (`--verify`); a
weakened fixture and a weakened probe in one diff still meet the
capture gate on the real spawn.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "each needing **CTO + CLO review and an ADR-075 addendum**" [issue #10032] | Phase 3.1 + 3.5; `## Architecture Decision (ADR/C4)` | mapped |
| 2 | "The `/proc` mask is the cross-tenant control from #9723 … Reverting the splice restores availability and re-opens #9723." [issue #10032] | FR/property P2; Phase 1.2 (neutralize, never revert); AC2/AC6 | mapped |
| 3 | "A procfs mask that does not require mounting a fresh procfs under a masked parent." [issue #10032, candidate fix 2] | Proposed Solution chosen shape; Phase 1 | mapped |
| 4 | "A procfs-free shim argv path — `sdk_noproc rc=0` is the first measurement that this class works on the real host." [issue #10032, candidate fix 3] | Folded into chosen shape (tail-bind neutralization is what makes procfs-free safe); Research Reconciliation | mapped |
| 5 | "`--security-opt systempaths=unconfined` … the scope of the widening needs review, not just the action." [issue #10032, candidate fix 1] | Review-gated fallback arm; Phase 0.5 decision gate | mapped |
| 6 | "least-privilege read for the deploy user … is a separate host-IaC plan with its own apply+gate" [issue #10032] | Phase 4.2 — deferred with tracking issue | descoped — justification: issue itself scopes it out of this fix |
| 7 | "#9860 stays open until the canary passes again." [issue #10032] | AC4 / Phase 4.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `infra/bwrap-shim/bwrap` rewrite | "the agent sandbox shim's required fresh procfs mount (`--proc /proc`, spliced in by #9768's shim to mask the host proc tail) cannot mount under docker's default masked `/proc`" | asked |
| fd re-home via `--ro-bind`/`--bind-data` ladder | "A procfs mask that does not require mounting a fresh procfs under a masked parent." | inferred — justification: the vendored multicall execs `/proc/self/fd/N`; a procfs-free /proc without re-homing breaks the spawn (P3), so the mask cannot ship without it |
| `proc_mask` probe re-spec | — | inferred — justification: the probe asserts `/proc/self/environ` exists, which a tmpfs mask makes false by design; an unre-spec'd probe reports a healthy fix as `sandbox_broken` (P5) |
| Phase-0 measurement spike | "sdk_probe EPERM, sdk_noproc rc=0 … the first measurement that this class works on the real host" | inferred — justification: rc=0 measured the simplified probe argv, not the vendored shape; the fd-type and /proc-dependency measurements select the realization rung before code is written |
| ADR-075 addendum + runbook + register | "each needing CTO + CLO review and an ADR-075 addendum" | asked |
| `ci-deploy.sh` fallback arm | "`--security-opt systempaths=unconfined` on the canary/agent container" | asked (as candidate) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: ~15 (14 edit + 1 create) | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the shim rewrite and its canary re-spec are
  one semantic change; splitting them ships an inconsistent boundary.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (88 issues)
grep'd for all 15 planned paths; zero body matches.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carry-forward from
`knowledge-base/project/brainstorms/2026-10-08-tenant-fs-isolation-brainstorm.md`
`## Domain Assessments` — same security boundary; assessment applies to
the mechanism change this plan makes).

### Engineering

**Status:** reviewed (carried forward; inline — no Task subagent tool in
this harness)
**Assessment:** CTO assessed the boundary design on 2026-10-08: the shim
layer is where argv control lives ("authors our own argv — immune to SDK
drift"); per-tenant executor (#9773) is the correct end-state but wrong
vehicle for an availability fix. This plan stays inside that guidance:
the rewrite is confined to the shim + canary, no new substrate. The
issue's "CTO review" mandate is re-run at `soleur:review` on the diff.

### Legal

**Status:** reviewed (carried forward + inline gdpr-gate, Phase 2.7)
**Assessment:** CLO on the parent design: `/proc` reads leave no audit
trail (Art. 33 accountability) — the observability probe is mandatory;
register entries in honest tense. Inline gdpr-gate this plan: canonical
regex matches zero file paths; invoked under trigger (b)
(single-user-incident threshold). Findings: no Art. 6/9/17/Chapter-V
items; two advisory rows — (1) keep `proc_mask` discriminating as the
sole breach-witness, (2) record the TOM mechanism change in
`compliance-posture.md`. No Critical findings; no escalation.

### Product

**Status:** reviewed (carry-forward; tier NONE)
**Assessment:** CPO: zero user-facing surface; claim discipline —
"process-level filesystem isolation for sandboxed agent commands",
never unqualified "tenant isolation". Product/UX Gate: tier **none**
(mechanical UI-surface scan of Files to Edit/Create: zero matches
against `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`,
`pages/**`, `routes/**`, `*.njk|html|vue|svelte|astro` — backend/infra
only). `requires_cpo_signoff` is driven by the User-Brand threshold,
not the UX gate.

**Brainstorm-recommended specialists:** none by name (the CLO's
"gdpr-gate at plan 2.7" is a skill invocation — run inline above —
not a specialist agent).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `apps/web-platform/infra/bwrap-shim/bwrap` emits no
  `--proc` token and no procfs mount at normalized dest `/proc` in the
  rewritten merged stream — pinned by `bwrap-shim.test.ts` over the
  committed fixture argv plus `--args`-payload and operand-boundary
  shapes.
- [ ] **AC2** On the prod image's bubblewrap (0.8.0), the rewritten
  argv spawns rc=0 under docker's DEFAULT masked `/proc`; in-sandbox
  `/proc` shows zero pid directories; every `/proc/self/fd/N` multicall
  reference resolves (spawn + exec succeed).
- [ ] **AC3** `sandbox-canary.mjs`'s re-spec'd `proc_mask` probe drives
  RED (`proc_mask_defeated` → `sandbox_broken`) when the tail bind is
  restored — mutation pinned in `sandbox-canary.test.ts` — and passes
  on the legitimate tmpfs mask.
- [ ] **AC5** ADR-075 addendum `## Addendum — 2026-10-11 (#10032)`
  committed in the same PR; runbook H6 row updated;
  `compliance-posture.md` register note landed; CTO + CLO review seats
  ran at `soleur:review` and their findings are dispositioned in the
  PR record.
- [ ] **AC6** `git grep -nE 'security-opt[= ]+systempaths'
  apps/web-platform/` returns zero hits (the fallback arm did not ship;
  scoped to the `--security-opt` token so doc/comment mentions of
  systempaths cannot false-fail it) — OR, if the Phase-0 gate selected
  the fallback, the addendum names the unmasked path set and the
  CTO+CLO review record carries the scope acceptance.
- [ ] **AC7** The `SOLEUR-DEBT` kdeny note in `ci-deploy.sh` is
  dispositioned (demoted or updated); the kernel-stream grant is
  tracked as #10045, not a prose deferral.
- [ ] **AC8** `sandbox-credential-deny-runtime.test.ts` re-measures
  green on the new argv (ADR-272 re-measure mandate on sandbox-flag
  changes); if the measurement moves, the plan is amended before merge,
  not silently.
- [ ] **AC9** `BASELINE_DECLARED_PROBES` in
  `plugins/soleur/test/preflight-discoverability-test.test.ts` is
  bumped +1 in this PR with the required PLACEMENT/TRUTH/NO-SUBSTITUTE
  comment (the `credentials_required` declaration above moves the
  corpus count).

### Post-merge (deploy)

- [ ] **AC4** The first prod deploy carrying the fix reports the
  faithful canary verdict `pass` (no `sandbox_broken` row,
  `SOLEUR_CANARY_SANDBOX_DIAG` does not fire) — the #9860 close
  condition.

## Test Scenarios

- Given the committed vendored fixture argv (tail `--bind /proc /proc`,
  `--args` payload, `--unshare-user --unshare-pid`), when it passes
  through the shim, then the emitted stream contains no procfs mount at
  `/proc`, the `--tmpfs /proc` from denyRead survives, and each
  `/proc/self/fd/N` command ref has a re-home mount — `integration`
- Given a payload-embedded tail bind (Arm-B shape), when consumed and
  re-emitted, then the payload's proc-exposing tokens are dropped and
  the merged stream stays mount-free at `/proc` — `integration`
- Given zero / two `/proc/self/fd/N` command refs, when rewritten, then
  zero / two re-home mounts are emitted (count asserted — the
  second-member and vacuity rows) — `unit`
- Given a multicall fd that is unreadable or O_PATH-only under the
  available rungs, when the shim processes the argv, then it exits 65
  with the `bwrap-shim:` marker — never a silent degrade — `unit`
- Given an argv with no `/proc` exposure, when rewritten, then it
  passes through byte-identical (the canary deploy-probe shape) —
  `unit`
- Given the prod image (bwrap 0.8.0, apparmor + repo seccomp, default
  masked `/proc`), when the rewritten argv runs in-image, then spawn
  rc=0, multicall resolves, `/proc` shows no pid dirs, host pid absent —
  `integration`
- Given the restored tail bind, when the re-spec'd `proc_mask` probe
  runs, then it reports `proc_mask_defeated` (RED-driving mutation —
  the probe is not a tautology) — `unit`
- Given a session Bash call on the fixed image, when the vendored
  multicall execs `/proc/self/fd/N`, then it resolves through the
  re-home mount — verified via the in-image verify harness —
  `integration`
- **API verify:** post-deploy, read the faithful-canary verdict via
  `doppler run -c prd -- scripts/betterstack-query.sh` on the
  `SOLEUR_CANARY_SANDBOX` / deploy-state surface — expects `pass` and
  zero `SOLEUR_CANARY_SANDBOX_DIAG` rows for the deploy window (the
  exact query lands in the work phase; the operator read path is the
  existing no-SSH channel, never journald-by-hand).

## Sharp Edges

- `sdk_noproc rc=0` is the control for the mount failure — NOT proof a
  procfs-free argv exists. The vendored tail bind must be neutralized
  in the same edit or the fix re-opens #9723 while reporting green.
- The prod bwrap is **0.8.0**: `--bind-fd`/`--ro-bind-fd` do not exist
  there (≥0.10.0). Any realization written against the dev host's 0.12
  that uses `--bind-fd` ships dead — measure and pin on 0.8.0
  (`--bind-data`/`--ro-bind-data`/`--file`/`--perms` only).
- Payload re-emit becomes selective: an `--args` payload carrying a
  proc-exposing token must lose it on re-emit — passing payloads
  "verbatim" is the exact hole the rewrite exists to close.
- `--opt=` equals-forms are the shim's documented known limit; restate
  in the code whether the rewritten parser inherits or narrows it —
  do not leave it ambiguous.
- The `proc_mask` probe's `/proc/self/environ` half dies BY DESIGN
  under tmpfs; deleting it without a replacement assertion leaves a
  canary that cannot fail (learning `2026-07-19-...`).
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO` text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Fallback arm note: `systempaths=unconfined` is ALL-OR-NOTHING — the
  docker masked list has no subset form; the only "narrower" version
  is not taking it.
- Deferred with tracking: least-privilege kernel-stream read for the
  deploy user (`kdeny src=none`) — separate host-IaC plan per the
  issue; tracked in the issue filed at plan time.

## Context

Refs: #10032 (this fix), #9860 (parent incident — closes on green
canary), #9723 + PR #9768 + PR #9803 (the mask control, preserved),
#9803 gating, PR #9938 (diagnostics), ADR-075 (addendum target),
ADR-272 (credential-deny re-measure), ADR-079 (faithful canary),
#9773 / #9842 (the funded end-state — out of scope), runbook
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
H6 row, brainstorm
`knowledge-base/project/brainstorms/2026-10-08-tenant-fs-isolation-brainstorm.md`,
`knowledge-base/project/plans/2026-10-08-feat-tenant-fs-isolation-plan.md`
Phase 0 (the prior measurement of this kernel restriction for the
outer-wrap arm).

## References

- Issue: [#10032](https://github.com/jikig-ai/soleur/issues/10032)
- bubblewrap#284 — masked `/proc` vs fresh procfs mount
- bubblewrap NEWS (0.10.0 `--[ro-]bind-fd`; ≤0.8.x `--bind-data`,
  `--file`, `--perms`)
- anthropic-experimental/sandbox-runtime#214 — same EPERM signature
  under stock docker/k8s; `enableWeakerNestedSandbox` is the upstream
  posture arm
