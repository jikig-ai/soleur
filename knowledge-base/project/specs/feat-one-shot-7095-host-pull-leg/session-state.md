# Session State — #7095 (PR-A: restore production)

Branch `feat-one-shot-7095-host-pull-leg`, draft PR #7097.

## Plan Phase — complete

Plan: `knowledge-base/project/plans/2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md`

**The issue's premise was falsified by measurement.** All three ADR-096 clause (f) suspects
(private NIC, `ZOT_PULL_*`, zot `accessControl`) are healthy. The real fault is one credential
level up and is a **second, distinct incident**: web-1's boot-baked full-`prd` Doppler service
token in `/etc/default/webhook-deploy` was revoked at **2026-07-30T11:19:30.614Z**, so
`doppler secrets get` returns empty → `ZOT_REGISTRY_URL` empty → the zot gate takes its
`"dark, pre-provisioning"` branch and never contacts zot → unauthenticated GHCR pull of a private
package → `auth_denied` → `image_pull_failed`. The two incidents share only that reason string,
which is why eight red releases read as one known incident.

## Work Phase — Phase 0 complete, implementation in progress

### Phase 0 measured results (recorded in the plan under `## Phase 0 Results`)

- **0.0 RESOLVED to branch (a)** — `/etc/default/inngest-server` DOES exist on web-1; the
  `web-probe-read-token.tf:5-6` parenthetical is stale. Two independent proofs: (i)
  `inngest-heartbeat.service` carries a NON-optional `EnvironmentFile` for it and ran healthy
  until 11:19:56; (ii) unit failure onset is +18.17s / +26.14s after the mint with zero failures
  in the preceding 53h, and since the ExecStart branches on `[ -n "$DOPPLER_TOKEN" ]`, an empty
  token would make behaviour invariant across the revocation — it flipped. **H7b CONFIRMED.**
- **0.4 — Terraform's copy of the token is ALIVE (HTTP 200)** and its rendered env line carries no
  CR/`#`/space/newline. This is the precondition the entire remediation rests on.
- 0.2 channel alive (`complete: 15/15 files written, 0 failed` @ 16:32:48); 0.2b apply workflow
  green @ 16:30:44 (root-SSH leg alive); 0.3 token state unmoved.
- Prod self-reports `version: 0.244.0` against latest tag v0.246.1.
- `web-{1,2}.app.soleur.ai` do NOT resolve (000) — the per-host origin probes R33 wants for PR-B
  do not exist as DNS today.

### Landed commits

| commit | content |
|---|---|
| `24bd9c143` | Phase 0 measured results into the plan |
| `f5278fe72` | `release-outcome` terminal job — alerts the operator on ANY failed release run |
| `d0e000920` | credential-delivery core (tmpl, server.tf render, var validation, payload/hooks/FILE_MAP/DEST_SPEC, envfile_shape + mkdir -p, gate tier-1/tier-2) |
| `ceba900b2` | consumer wiring (3 units, 2 drop-ins, ci-deploy-wrapper source) + de-hardcoded 9 literal `15`s |
| `78142fc64` | apply-workflow `paths:` + R34 webhook-down branch + R22 falsification recorded |

### Suite status at last run

`infra-config-gate` 18/18 · `infra-config-install` 31/31 · `infra-config-apply` 63/63.

### Review revisions that did NOT survive contact (recorded in the plan)

- **R22 FALSIFIED.** `deploy_pipeline_fix` `depends_on` `infra_config_handler_bootstrap`
  (`server.tf:1306`), which writes the new `hooks.json` (`:1204`) and restarts the listener
  (`:1219`) before the push. The #5515 edge exists for exactly this scenario. A second apply pass
  would guard an unreachable state, and would be a no-op without `-replace` anyway.
  **Residual (real, deliberately deferred):** the verify step only re-polls and never re-POSTs, so
  it cannot recover from the documented nonce-1 race. Fixing it means putting `continue-on-error`
  on the fail-closed gate whose latched false-green (#6594) let this outage class hide — not a
  change to make under outage pressure.
- **R27 CONFIRMED** by an independent slice: `web-platform-release.yml`'s `case` at `:706` is on
  `$EXIT_CODE`, not on reason, and already echoes the reason at `:728-732`. No edit needed there.

### In flight (background agents, strict file ownership)

1. `ci-deploy.sh` + `ci-deploy.test.sh` — credential-read diagnostics (`SOLEUR_DEPLOY_CRED_FAIL
   rc= empty= err=`), `MOCK_DOPPLER_GET_FAIL` seam, positive controls, fail-OPEN preserved per R25.
   **Observability only — no new abort path.**
2. Five-way lockstep parity — `ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES`,
   `ship/SKILL.md` `DEPLOY_PIPELINE_FIX_TRIGGERS` + `DPF_REGEX`, `cron-egress-firewall.test.sh`
   order assertion (mutation-tested).
3. `cloud-init.yml` fresh-host parity — must consume the ALREADY-RENDERED string (R8: render once,
   inject) and report the one-line `server.tf` change needed.

### Exit gates — BOTH runners, against a clean committed tree

| gate | rc | result |
|---|---|---|
| `scripts/test-all.sh` | 0 | 239/239 suites |
| `apps/web-platform/infra/run-registered-suites.sh` | 0 | 87/87 suites, zero orphans |

Both required: `test-all.sh` does NOT cover `apps/web-platform/infra/` and says so in its preamble.
An earlier `test-all.sh` run was KILLED rather than interpreted — files were edited while it was
in flight, which makes its output a mid-refactor snapshot of the author's own making.

### Follow-ups filed (net flow: 0 closed, 2 filed, +2 — stated deliberately)

- **#7103** — consolidated PR-B tracker (telemetry off the box, credential liveness, staleness
  alerting, the 19-of-19 web-1 pinning, ADR-154 + PIRs).
- **#7104** — the R22 residual, kept SEPARATE as a discovered defect in a different subsystem:
  the apply-verify step re-polls but never re-POSTs, so it cannot recover from the documented
  nonce-1 webhook-restart race.

#7095 itself stays OPEN and was re-titled — its original title named the falsified premise
(`ZOT_PULL_*`/private NIC), which actively misleads anyone triaging a live P1. A correcting
comment carries the E1–E5 evidence; the original body is left intact for the record.

### Remaining after those land

- Apply the `server.tf` `user_data` key the cloud-init slice reports.
- Full-suite exit gate: `scripts/test-all.sh` AND `apps/web-platform/infra/run-registered-suites.sh`
  (the diff touches `apps/web-platform/infra/`, which `test-all.sh` does NOT cover).
- `/review` → `/qa` → `/compound` → `/ship`.
- Post-mortem stays `status: ongoing` until prod genuinely deploys again.

---

## Round-3 findings — the three merge-blocking ones are FIXED and mutation-proven

Original heading was "STOP — DO NOT MERGE AS-IS". The three gaps that could silently ship a
broken credential are closed; F13/F14/F16 remain open and are P2 (see the disposition at the
bottom of this section).

Round-3 review executed **11 mutations that each violate a property this PR claims, while
leaving the suites fully green**. The PR's two headline claims — "mutation-proven" and "counts
are derived, not hardcoded" — do not survive. Test Quality Score 6.9/10 (C), down from 7.25.

### The single highest-value gap: the `.conf` drop-in mechanism has ZERO content assertions

It carries the credential to the two units this PR itself calls most critical (`vector.service`,
`inngest-heartbeat.service`) — now three, with `inngest-server.service`. It is **structurally
invisible** to the `cron-egress-firewall.test.sh` sweep, which globs `*.service` and so cannot
see a `.conf` by construction. Mutations that stayed GREEN:

- gut both `.conf` files to a bare `[Service]` line (drop-in does nothing)
- re-point the heartbeat drop-in at `/etc/default/inngest-server` — **the dead file that caused
  this outage**
- invert tier-2 into a guard that rejects every correct apply

Fix: assert per `10-*-doppler-token.conf` that it contains exactly
`EnvironmentFile=-/etc/default/soleur-doppler-token`, with a floor of 3 and a KNOWN list
mirroring `DOPPLER_COPY_KNOWN` (growth free, shrinkage loud).

### Remaining findings, all verified by executed mutation

| # | Sev | Finding |
|---|---|---|
| F11 | P1 | `empty=` is a ONE-valued constant. Mutating `empty=${CRED_EMPTY}` → `empty=1` stays 196/196. Both fixtures report `empty=1`, so the field whose whole purpose is distinguishing the `rc=0 empty=1` shape carries no checkable information. |
| F12 | P1 | The retry UPPER bound is unpinned. Default `_tries` 2 → 8 passes, printing "retried (8 attempts)". `-ge 2` pins that retry happens, never that it stops. Use `-eq`. |
| F13 | P2 | "an rc=0 empty read is NOT retried" is argued at length in the code and tested nowhere — deleting the break line leaves all 8 new tests green. |
| F14 | P2 | "REDACTION MUST PRECEDE TRUNCATION" is untestable as fixtured — the canary sits inside the 200-byte window, so truncate-first still passes. Needs a canary straddling the boundary. |
| F15 | P2 | The P1 credential-leak fix that landed mid-review (`dp\.st\.` → `dp\.[a-z]{2,}\.`) is UNTESTED — reverting to the narrow pattern still passes. No `dp.sa.` / `dp.pt.` fixture. |
| F16 | P2 | The credential-CONSUMPTION path has zero coverage: **0** references to `soleur-doppler-token` in either ci-deploy suite. Nothing pins that a hostile file cannot execute, that the token is actually overridden, or that an absent file is a no-op under `set -e`. |
| meta | P1 | `cdf6197e3` changed `ci-deploy.sh` by 83 lines — a source→parse code-execution fix and a credential-disclosure fix, both self-described P1 — with ZERO test changes, suite 196/196 before and after. |

### Diagnosis of the pattern

**Fixture DIRECTION.** Nearly every gap is one missing fixture on the other side of a transform.
Confirmed non-findings (do not re-hunt): the `| tail`/pipefail/SIGPIPE class is genuinely handled
(`set +e +o pipefail` around the block); `cq-assert-anchor-not-bare-token` is satisfied (assertions
grep the runtime capture, not the source); T-7095-3's control-char and length bounds have real
teeth; T-7095-5/6 are properly paired with positive controls.

### Gate status at handoff

BOTH GATES GREEN against the clean tree:

| gate | rc | result |
|---|---|---|
| `scripts/test-all.sh` | 0 | 239/239 suites, no contention banners |
| `apps/web-platform/infra/run-registered-suites.sh` (solo) | 0 | **87/87 suites** |

The `ci-deploy.test.sh` RED seen earlier is **CONFIRMED contention**, not a defect — it failed
only under `-P 6` with a concurrent `test-all`, passed `rc=0 196/196` on three isolated runs (one
timed at 291s), and the solo gate run is 87/87. Recorded as confirmed rather than assumed: an
earlier discriminator in this session ("no `FAIL:` line means it aborted") was WRONG — the runner
prints only PASS/RED per suite and captures no per-suite output, so absence of a `FAIL:` line
carries no information. The valid evidence is the isolated runs plus the solo gate.

**Recommendation: fix the drop-in content guard and F11/F12 before merge.** Prod is stable on
stale v0.244.0; that is a cheap state. A bad fix in the sole no-SSH remediation channel on an
unreplaceable host is not.


---

## Round-3 disposition (2026-07-31)

### Fixed and mutation-proven in both directions

| gap | mutation that was GREEN | now |
|---|---|---|
| `.conf` drop-in content guard | gut a drop-in to bare `[Service]` | **FAIL** |
| | re-point a drop-in at `/etc/default/inngest-server` (the dead file) | **FAIL** (both assertions) |
| | delete a drop-in entirely | **FAIL** (floor + membership) |
| F12 retry upper bound | `_tries` default 2 → 8 (printed "retried (8 attempts)") | **FAIL** |
| F11 `empty=` one-valued | hardcode `empty=1` in the emitter | **FAIL** |

Every mutation restored byte-identical against a pristine backup (`diff -q`), baseline green
before and after. `cron-egress-firewall` 216/216 (was 206); `ci-deploy` 197/197 (was 196).

The `.conf` gap was STRUCTURAL, not an oversight: the doppler-copy sweep globs `*.service`, so a
`.conf` is invisible to it by construction — and widening that glob would be wrong, because its
order assertion is meaningless for a drop-in (systemd merges drop-ins after the main unit, so
later-wins is structural rather than line-ordered). A separate sweep was the right shape.

### ALL SIX round-3 findings are now CLOSED and mutation-proven (2026-07-31)

| gap | mutation | verdict |
|---|---|---|
| F13 no-retry-on-empty | delete the break line (retry everything) | **RED**, `rc=0-empty attempts=2` |
| F14 redact-before-truncate | truncate-first ordering | **RED**, `TAILMARKER` leaks |
| F16 consumption path | source-instead-of-parse | **RED**, mutant executes the file |

F16's block is EXTRACTED FROM THE SHIPPED SOURCE and executed rather than reached via a new env
override — an override redirecting which credential file is read is a production surface, and
adding one to test credential-reading code is the wrong trade. Path literal pinned separately:
(a)-(d) pin the LOGIC, (e) pins the PATH, plus a non-vacuity guard on the extraction.

`ci-deploy` 201/201 (was 196 at round-3 start).

### Superseded — the original deferral rationale, kept for the record

- **F13** — "an `rc=0` empty read is NOT retried" is argued at length in the code and tested
  nowhere; deleting the break line leaves all the new tests green.
- **F14** — "REDACTION MUST PRECEDE TRUNCATION" is unobservable as fixtured: the canary sits
  inside the 200-byte window, so truncate-first still passes. Needs a canary straddling the
  boundary.
- **F16** — the credential-CONSUMPTION path has zero coverage (0 references to
  `soleur-doppler-token` in either ci-deploy suite). Nothing pins that a hostile file cannot
  execute, that the token is actually overridden, or that an absent file is a no-op under `set -e`.
  NOTE: the code itself is now a keyed parse loop (not `source`), so the execution class is closed
  by construction; what is missing is the regression guard, not the fix.

Rationale for deferring these three and not the first three: none of them can silently ship a
BROKEN CREDENTIAL. F13/F14 are properties of the diagnostic's shape; F16 is a missing regression
guard on code that is already correct by construction. The three fixed ones could each have left
a consumer pointing at the dead token with every suite green.

### Gates at this point — both green, clean tree

| gate | rc | result |
|---|---|---|
| `apps/web-platform/infra/run-registered-suites.sh` (solo) | 0 | **87/87** |
| `scripts/test-all.sh` | 0 | **239/239** |

`test-all`'s run predates the last two commits, but those touched ONLY
`apps/web-platform/infra/**`, which `test-all` explicitly does not cover (it says so in its own
preamble) — verified with `git diff --name-only`. Its result still describes the current
non-infra tree.
