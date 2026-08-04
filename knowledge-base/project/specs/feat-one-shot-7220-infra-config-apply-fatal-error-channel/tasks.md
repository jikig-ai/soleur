---
feature: feat-one-shot-7220-infra-config-apply-fatal-error-channel
issue: 7220
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-03-fix-infra-config-apply-daemon-reload-denied-fatal-channel-plan.md
ships_as: two PRs (PR-A instrument, PR-B privilege)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **Phase 2.8 ack.** Every `systemctl` reference below is a line *inside* `infra-config-apply.sh` —
> a script delivered to the host by `terraform_data.infra_config_handler_bootstrap` + `cloud-init.yml`
> — or an assertion inside an existing Terraform `remote-exec`. Never a step a human runs. The one
> privilege change (a sudoers alias) ships through the same Terraform resource. Zero operator SSH,
> zero manual provisioning; the operator-gated `terraform apply -replace` is explicitly declined.

# Tasks — #7220 infra-config fatal channel + ungranted daemon-reload

Root cause CONFIRMED from prod telemetry: the reload call at
`apps/web-platform/infra/infra-config-apply.sh:415` runs as `User=deploy` with no sudoers grant,
returns `Interactive authentication required`, and `set -e` aborts the handler **after 19/19 files
are written** but before unit reconciliation and the webhook self-restart.

**Ships as two PRs.** PR-A carries no privilege change; PR-B must not open until PR-A is live.

---

## Phase 0 — Preconditions (no edits)

- [x] 0.1 Re-run `scratchpad/errtrap.sh` + `scratchpad/p0verify.sh` against **the target image's**
      bash (Ubuntu 24.04 / 5.2.x). Plan measurements are from 5.3.9.
- [x] 0.2 Read `infra-config-apply.test.sh:401` (`test_exit_trap_unhandled`), `:633`
      (`test_dropin_restart_grant`), `:1051` (`test_sudoers_caller_argv_lockstep`). Most new
      assertions **extend these**; do not add parallel arms. `test_exit_trap_unhandled` aborts
      *inside* the write loop, so it cannot cover the abort-before-counters case — that needs a new arm.
- [x] 0.3 Confirm phase order against the plan's `## Delivery split` before starting.

---

## PR-A — the instrument (no privilege change, no behaviour change)

### A1 — Trap hoist (AC7)
- [x] A1.1 Move `START_TS`, `rm -f "${STATE_FILE}.final"`, `rm -f "$STATE_FILE"` **above** the
      `RESTART_SETTLE_SECS` guard at `:146-150`.
- [x] A1.2 Install the ERR + EXIT traps immediately after `LOG_TAG` (`:19`).
- [x] A1.3 Test: a non-numeric `INFRA_CONFIG_RESTART_SETTLE_SECS` now yields a real frame with
      `fatal_rc=64` instead of serving the previous run's frame.

### A2 — ERR trap (AC8, AC9)
- [x] A2.1 Add `set -o errtrace`.
- [x] A2.2 Install the **pure-assignment** ERR trap — no `logger`, no subshell, no sanitizer:
      `trap 'FATAL_RC=$?; FATAL_LINE=$LINENO; FATAL_CMD=$BASH_COMMAND; …' ERR`.
      Inline comment: the single quotes are load-bearing (double quotes pin the trap's own line forever).
- [x] A2.3 Hand the triple over via **`"$STATE_FILE.fatal"`**, not variables — a subshell fatal
      assigns in the child and the parent would otherwise write a frame with no attribution.
- [x] A2.4 Add a **logger env seam** on the fatal emitter, adopting the precedent idiom
      `"${CUTOVER_LOGGER_CMD:-logger}"` from `inngest-cutover-flip.sh:145` (AC14b). Lets one test arm
      intercept the fatal channel specifically instead of relying on the global PATH shim.

### A3 — EXIT trap (AC10, AC11) — **P0**
- [x] A3.1 Convert the inline trap at `:221-224` to a named `on_exit()`.
- [x] A3.2 In order: capture `rc=$?`; `trap - ERR` as the **first** statement; all work `|| true`;
      end with `exit "$rc"` to re-pin the original status. `trap - ERR` alone is **not** sufficient
      — measured, a failing command in an armed EXIT trap turns `exit 0` into rc=1. The
      capture-first + `exit "$rc"` shape is exactly the precedent's `on_unexpected_exit`
      (`inngest-cutover-flip.sh:208-218`); copy it rather than inventing.
- [x] A3.3 Sanitize `cmd` with the existing `r_err_safe` idiom (`:497`).

### A4 — Frame fields (AC12, AC13)
- [x] A4.1 Emit `fatal_rc`/`fatal_line`/`fatal_cmd` **unconditionally**, zeroed when ERR never fired
      (one branchless `printf`).
- [x] A4.2 Replace the hardcoded `0 0 0` with `"${WRITTEN_COUNT:-0}" "${FAIL_COUNT:-0}"
      "${TOTAL_COUNT:-0}"`. **The `:-0` defaults are mandatory** — the trap is installed above
      `WRITTEN_COUNT=0` (`:240`) and a bare expansion under `set -u` writes **no frame at all**.
- [x] A4.3 No `accounting:` enum (cut at review — derivable, and it could not express the #7220 shape).

### A5 — Frame blind spot (first half of AC-B3)
- [x] A5.1 Move the `.final` touch (`:549`) to **after** a successful `mv`, so "completed but
      frame-publish failed" stops collapsing into "never ran".

### A6 — Gate message (AC15, AC16)
- [x] A6.1 `infra-config-gate.sh` renders a fatal `::error::` containing: `infra-config-apply.sh:<line>`
      + sanitized command; **"every step after this line did not run"**; `files_written=N of M
      delivered`; the next command using **`--since 1h`**; and the **`-replace` guardrail** verbatim.
- [x] A6.2 When `fatal_line` is present, suppress the branch anchored on
      `UNDER-DELIVERED: host reported files_total=` and the per-unit branch anchored on
      `no verdict for`. **Keep** the `exit_code != 0` line — it is accurate. Verified against the
      real frame: only two branches fire, not three (`files_written != files_total` does not, since
      0 == 0). Anchor on content, not line numbers.
- [x] A6.4 **Fail-OPEN guard:** the suppression must change only the MESSAGE, never the VERDICT.
      Add a test arm asserting a frame with `fatal_line` still FAILS the gate, and enumerate in the
      gate's comments every path that reaches `exit 0`.
- [x] A6.3 `infra-config-gate.test.sh` arms asserting the **rendered text** (never `grep -c` on an
      identifier — that is satisfied by a comment).

### A7 — Alerting (AC17) — **P0**
- [x] A7.1 Add an `if: failure()` step to `apply-deploy-pipeline-fix.yml` on the infra-config gate
      path, reusing the proven `seccomp_unenforced_alert` pattern (plain-language GitHub issue +
      Sentry). Today the only alerting path sits inside an `if: success()` step and never fires here.
- [x] A7.2 Correct the plan's Observability `alert_route` to match.

### A8 — Tests
- [x] A8.1 Subshell-fatal arm — `fatal_line` still reaches the frame.
- [x] A8.2 Abort-before-counters arm — a well-formed frame is still written.
- [x] A8.3 Secret-value sanitization fixture — a failing command referencing a secret-bearing
      variable must not leak the **value** to `$LOGGER_LOG` or the frame.
- [x] A8.4 Clean-apply-exits-0 arm (guards A3).

### A9 — Exit gate
- [x] A9.1 `bash apps/web-platform/infra/run-registered-suites.sh` (its own entry point, not a
      hand-enumerated list).
- [x] A9.2 `scripts/test-all.sh` — 254/255. The two REDs (`git-data-luks`, `inngest-doublefire-probe`)
      are parallelism-sensitive under the nested runner and NOT from this diff: both PASS in the
      CI-registered runner at the same commit (87/87), PASS 3/3 in isolation, contain zero
      references to any changed file, and `infra-validation.yml` is green on main.

---

## PR-B — the privilege (opens only after PR-A is live and reading)

### B1 — Shape gate (AC-B1) — **BLOCKING, lands first**
- [ ] B1.1 Extend `infra-config-install.sh`'s content gate to `/etc/systemd/system/*.service`.
      Today that dest matches **neither** the `/etc/default/*` gate (`:160`) nor the
      `*.service.d/*.conf` gate. Use a **content/digest pin** — a directive grammar cannot forbid
      `ExecStart=` on a full unit.
- [ ] B1.2 Test: an unpinned `webhook.service` payload is REJECTED.
- [ ] B1.3 Do not merge any other PR-B task ahead of this one.

### B2 — Grant
- [ ] B2.1 Add the reload `Cmnd_Alias` + `deploy ALL=(root) NOPASSWD:` line to
      `deploy-inngest-bootstrap.sudoers`.
- [ ] B2.2 Mirror it into `cloud-init.yml` (indented inside the YAML block — the suite compares with
      `^[[:space:]]*` normalisation, **not** byte-equality).

### B3 — Seam reuse (AC1, AC2)
- [ ] B3.1 Rename `SYSTEMCTL_RESTART` → `SYSTEMCTL_PRIV` (env name `INFRA_CONFIG_SYSTEMCTL`
      unchanged) **atomically with** `test_sudoers_caller_argv_lockstep`'s `sed` pattern at `:1068`,
      or the assertion silently compares against `""`.
- [ ] B3.2 Route the reload through `$SYSTEMCTL_PRIV`. No third env var — same privilege domain.
- [ ] B3.3 Update the `:121-128` taxonomy comment inside its existing WRITE paragraph.
- [ ] B3.4 Extend `test_sudoers_caller_argv_lockstep` to assert the reload argv is among the granted
      commands (derived from source on both sides, not a restated literal).

### B4 — Guard split (AC5)
- [ ] B4.1 Split `:413-416`: `sync` stays inside `if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]`; the
      seamed reload moves **out**. Without this the reload arms execute zero lines of the code they
      claim to cover and register as passing.

### B5 — Self-restart hardening (AC-B2) — **P0**
- [ ] B5.1 Make the orphan sweep's `jq` parse failure a hard per-file failure (today
      `command -v jq`-guarded + `|| true`, so an invalid `hooks.json` passes delivery and would
      activate 3 s later, leaving webhook serving **zero hooks** with the port still answering — the
      404 branch then gives the wrong diagnosis).
- [ ] B5.2 Add `--collect` to the transient unit, **and** update the `WEBHOOK_SELF_RESTART` argv in
      **both** sudoers copies in lockstep (`sudoers:30`, `cloud-init.yml:90`) or it becomes denied.
- [ ] B5.3 Add `StartLimitIntervalSec=0` to `webhook.service`'s `[Unit]`.

### B6 — On-host assertions (AC4, AC-B4)
- [ ] B6.1 `server.tf` `remote-exec`: `sudo -n -l` policy probe for the reload argv (a name-only
      `grep -q` passes for an alias never granted to `deploy`).
- [ ] B6.2 `DropInPaths` assertions for `inngest-heartbeat.service` and `inngest-server.service` —
      their entire activation story is the reload being repaired.

### B7 — Tests
- [ ] B7.1 Extend `test_dropin_restart_grant` for the new alias.
- [ ] B7.2 Reload-**denied** arm (one verb-dispatching stub, `case "$1" in`): asserts
      `SOLEUR_INFRA_CONFIG_FATAL` with non-zero `line=` and an empty `restarts[]`.
- [ ] B7.3 Reload-**success** positive control: asserts `SOLEUR_INFRA_CONFIG_RESTART` is emitted
      **and zero** `SOLEUR_INFRA_CONFIG_FATAL` markers (AC14).
- [ ] B7.4 Non-vacuity assertions on both arms (mirror `:1085-1090`).

### B8 — Class closure (AC6)
- [ ] B8.1 Handler→grant lint scoped to `infra-config-apply.sh`: every non-READ systemd verb must be
      `sudo`-prefixed **and** granted in both sudoers sources. READ allowlist: `show`, `is-active`,
      `is-enabled`, `cat`, `status`, `list-units`. Fail closed on zero derived invocations.
- [ ] B8.2 **Prove it RED against `main`** — the only evidence it would have caught #7220.

### B9 — ADR / C4
- [ ] B9.1 Amend ADR-159 `## Decision` (privilege precondition; load ≠ weaker restart).
- [ ] B9.2 Amend ADR-159 `## Consequences` — the "after the daemon-reload the handler already
      performs" clause is **falsified**; correct the two duplicate sites too
      (`infra-config-apply.sh:106-108`, `deploy-inngest-bootstrap.sudoers:118-123`).
- [ ] B9.3 Correct `model.c4:431`: the falsified "the handler now restarts the units it configures"
      clause **and** extend the invariant text to name the load step and record the `*.service` gap.
- [ ] B9.4 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### B10 — Post-merge verification (AC20, AC21)
- [ ] B10.1 Add the `start_ts` freshness pin to the verify assertions — every other value is
      satisfiable by a **stale** frame.
- [ ] B10.2 Write `scripts/followthroughs/infra-config-activation-7220.sh` (≥1
      `SOLEUR_INFRA_CONFIG_RESTART` for `vector.service`, field-isolated on `SYSLOG_IDENTIFIER`;
      **zero** `SOLEUR_INFRA_CONFIG_FATAL`; elapsed-time guard).
- [ ] B10.3 Add the `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive + the
      `follow-through` label. **Without this `gh pr ready` is denied** by
      `.claude/hooks/ship-soak-followthrough-gate.sh`.

### B11 — Exit gate
- [ ] B11.1 `run-registered-suites.sh`, then `scripts/test-all.sh`.

---

## Deferred — file as issues during /work

- [ ] D1 `betterstack-query.sh --since` ISO papercut: the header advertises "ISO" but the canonical
      `Z`-suffixed form is pasted verbatim into SQL and rejected by ClickHouse. AC15's `--since 1h`
      removes it from every command this plan prescribes, which is why it does not gate here.
- [ ] D2 Extract a shared `infra-fatal-trap.sh` — this is the **fourth** bespoke fatal trap
      (`ci-deploy.sh:471` is stderr-only, no `errtrace`, non-`SOLEUR_*` marker, so its fatal line
      never leaves the host).
- [ ] D3 Restore `-replace` as a real lever (second web host / instance type) per ADR-154 — the
      reason this channel carries so much ceremony.
- [ ] D4 Journald R1-1.8a/b/c triad for `infra-config-apply.sh` (cut from scope: guards a file this
      PR does not touch; one reviewer dissented, rating it near-zero-cost).

## Gates

- CPO sign-off required (`brand_survival_threshold: single-user incident`, raised at review).
- `security-sentinel` + `user-impact-reviewer` mandatory at review time for **PR-B**.
- No production write in this workflow. `terraform apply -replace` is **declined** with evidence —
  see the plan's `## Operator-Gated`.
