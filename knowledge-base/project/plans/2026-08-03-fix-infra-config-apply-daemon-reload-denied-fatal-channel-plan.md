---
title: "fix(infra): the config channel dies at an ungranted daemon-reload, and its own frame says the opposite"
issue: 7220
type: bug
priority: p1-high
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-08-03
ships_as: two PRs (PR-A instrument, PR-B privilege) — see ## Delivery split
branch: feat-one-shot-7220-infra-config-apply-fatal-error-channel
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **Phase 2.8 ack rationale.** Every `systemctl` reference in this plan is *the subject of the bug* —
> a line inside `infra-config-apply.sh`, a script delivered to the host by
> `terraform_data.infra_config_handler_bootstrap` + `cloud-init.yml`, never a step a human runs.
> The one privilege change (a sudoers alias) is delivered by the same Terraform resource and is
> documented in `## Infrastructure (IaC)`. This plan prescribes **zero** operator SSH, zero manual
> provisioning, and explicitly declines the operator-gated `terraform apply -replace` it was handed
> (see `## Operator-Gated`).

# fix(infra): the config channel dies at an ungranted `daemon-reload`, and its own frame says the opposite

> Lane note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).
>
> **Revision R2** — rewritten after a 6-agent review panel. Every P0 below was found by review, not
> by the original draft; two of them would have made the instrument worse than the bug.

## Overview

`infra-config-apply.sh` aborts on prod at `systemctl daemon-reload` (`:415`), which the `deploy`
user is not authorised to run. Under `set -euo pipefail` that kills the handler **after all 19
FILE_MAP files are written** but **before** the RESTART_MAP reconciliation and the webhook
self-restart. The EXIT trap then publishes a frame whose counters are hardcoded zeros, so the CI
gate reports `files_total=0` — the exact opposite of what happened.

Root-caused from production telemetry, not inferred. See `## Evidence`.

Three things ship:

1. **The privilege fix** — a pinned sudoers alias plus reuse of the existing WRITE seam, so the
   activation half of ADR-159 can actually execute. *This is the only change that fixes production.*
2. **The fatal-error channel** — an `ERR` trap that names the failing line/command/rc, carried in
   **both** journald and the state frame.
3. **A truthful, actionable operator message** — so the gate stops asserting a non-delivery that did
   not happen, and so the next annotation does not point the operator at `terraform apply -replace`
   on a host that cannot be replaced.

### What is actually degraded (corrected from the issue body)

Config **delivery is healthy**. Config **activation is not**. All 19 files reach the host on every
apply; no unit ever re-reads them, because the handler dies one line before the reconciliation
loop. That is precisely the failure mode ADR-159 and PR #7146 were written to end — reintroduced
by #7146's own reordering.

## Evidence

Pulled read-only from Better Stack in-session (`scripts/betterstack-query.sh`, source 2457081,
`host_name=soleur-web-platform`, window `2026-08-03 11:55–12:02Z`). No production write was made.

**The failing command, with its own error text**, on webhook request id `86ea60` — the same id as
the handler's exec line:

```text
11:58:30.684  [webhook]            [86ea60] executing /usr/local/bin/infra-config-apply.sh …
11:58:30.694  [infra-config-apply] starting: 19 files to write
11:58:30.698  [infra-config-apply] writing: /usr/local/bin/ci-deploy.sh
   … 19 write/wrote pairs, no failures …
11:58:31.739  [infra-config-apply] complete: 19/19 files written, 0 failed
11:58:31.782  [webhook]            [86ea60] command output: Reload daemon failed: Interactive authentication required.
```

Nothing follows. `SOLEUR_INFRA_CONFIG_RESTART` (emitted **unconditionally**, once per RESTART_MAP
unit, at `:537`) never appears, and neither does `scheduling self-restart in 3s` (`:583`). The
state frame the CI gate read:

```json
{"schema_version":2,"start_ts":1785758310,"end_ts":1785758311,"exit_code":1,
 "reason":"unhandled","files_written":0,"files_failed":0,"files_total":0,"files":[],"restarts":[]}
```

`start_ts`→`end_ts` is 1 s, matching the measured 1.05 s write loop. `schema_version:2` exists only
in the post-#7146 trap, and `:208` `rm -f "$STATE_FILE"` runs at handler entry — so the frame is
**this run's**, not a latched one.

### Premise corrections

| Issue-body claim | Reality | Source |
|---|---|---|
| "delivering zero of its 19 FILE_MAP entries" | **19/19 written, 0 failed.** `files_total:0` is a hardcoded no-accounting sentinel (`:211-214`), never a measurement | journald tail above |
| "emitted NOTHING to journald … died BEFORE its first `logger` call" | **40 rows shipped**, including all 19 writes and `complete: 19/19` | Better Stack query |
| "a Better Stack query … returns zero rows … that absence is real" | Rows exist. The original query was mis-scoped; `--grep` terms OR-combine and there is no `--host` flag (`betterstack-query.sh:101-131`, `:179-187`) | verified against current source |
| Suspect 1 — `INFRA_CONFIG_RESTART_SETTLE_SECS` guard / `unit_prop` / `RESTART_MAP` | **Refuted 3×**: the guard `exit 64`≠1; it emits `SOLEUR_INFRA_CONFIG_CONFIG_INVALID` (absent); the restart loop was never reached | `:146-150`, `:221` |
| Suspect 2 — `*_B64` env-contract skew killing the handler under `set -u` | **Refuted**: 19 = 19 = 19 set-equality across `push-infra-config.sh` / `FILE_MAP` / `hooks.json.tmpl`; every read is `${!env_var:-}`-guarded (`:250`); the mechanism is `pass-file-to-command`, not `pass-environment-to-command`; all 19 payload paths were present and written | agent audit + webhook exec line |
| "the documented recovery is `terraform apply -replace=…`" | **Not required.** That lever is for a *bricked webhook*. The listener answered 200 and the SSH bootstrap leg ran cleanly in this very apply | run 30811367645 |

### Not new — moved

`git log -S 'systemctl daemon-reload' -- apps/web-platform/infra/infra-config-apply.sh` returns a
single commit, `fc8b81796` (#3756/#4492, May 2026). #7146 **moved** `sync` + `daemon-reload` from
*after* the state write to *before* it.

- **Before:** the frame was sealed, then the reload failed → CI green, self-restart silently
  skipped. A #4804-class silent freeze.
- **After:** the frame is not yet sealed → the EXIT trap fires → CI fails loud.

So #7146 did not introduce the defect; it made a ~2-month-old silent failure visible. Every green
infra-config apply since May 2026 is compatible with the reload having always been denied — a
plausible contributing cause of the stale drop-ins #7146 was written to fix.

## Measured bash semantics (the plan's load-bearing claims, tested not argued)

All measured on bash 5.3.9; prod is Ubuntu 24.04 / bash 5.2.x. Semantics are stable across 4.4+,
and Phase 1.0 re-runs the harness on the target image.

**(a) No false fatals.** Every guarded idiom the handler already uses stays silent under
`set -o errtrace`:

| Handler idiom | Site | ERR fired? |
|---|---|---|
| `v=$(unit_prop …) \|\| flag=0` | `:434`, `:447`, `:499`, `:513-517` | **no** |
| `[[ cond ]] && x=y`, test false | `:469` | **no** |
| `[[ cond ]] && x=y \|\| true` | `:516`, `:518` | **no** |
| `if false; then …; fi` | throughout | **no** |
| `err=$(cmd 2>&1 >/dev/null) \|\| rc=$?` | `:481` | **no** |
| **unguarded failing command** | **`:415` — the real one** | **yes** — `rc=1 line=<n> cmd=<text>` |

Corollary worth recording: the comment at `:508-511` claiming `set -e` "would abort" on a bare
`[[ ]] && x=y` is **wrong** — bash exempts every command in an AND-OR list except the last. The
`|| true` at `:516`/`:518` is harmless but not load-bearing.

**(b) The ERR trap stays armed during the EXIT trap — and that is a P0 hazard.** Measured: with an
ERR trap installed, a failing command inside the EXIT trap fires the ERR handler **and rewrites the
script's exit status**. A script whose last statement was `exit 0` exited **1**, with
`ERR_FIRED cmd=[exit 0]`. Today's EXIT trap is fully guarded so this is latent; enriching it
(sanitizer pipeline, extra args) would arm it. **`trap - ERR` is necessary but NOT sufficient** —
measured separately, it suppresses the spurious marker while the failing command still flips rc.
The EXIT trap must therefore capture `rc=$?` first, `trap - ERR` immediately, guard every command
with `|| true`, and end by re-pinning the status.

**(c) An EXIT trap that expands an unset variable under `set -u` writes nothing at all.** Measured:
`NEVER_SET: unbound variable`, and the frame was never written — `2>/dev/null || true` does **not**
save it, because the expansion aborts before the command runs. This makes `${VAR:-0}` mandatory,
not stylistic.

**(d) `BASH_COMMAND` on a bare pipeline names the *last* element**, not the failing one
(`false | cat` → `cmd=[cat]`). Assignment-wrapped pipelines (`s=$(a | b)`, the `:309`
`sha256sum | awk` shape) report the whole assignment and the pipefail rc, so the handler's real
sites are fine. Record it so the field is not over-read.

**(e) A failure inside an explicit subshell loses the `FATAL_*` triple** — the assignments happen in
the child and die with it. This is why the triple is handed over through a **file**, not variables.

Harness: `scratchpad/errtrap.sh`, `scratchpad/p0verify.sh`.

## Hypotheses

The Phase 1.4 network-outage gate fired (the description names `terraform apply -replace` on a
resource with `provisioner "remote-exec"` + an SSH `connection` block, and contains "SSH").
Layers, L3→L7:

1. **L3 — firewall allow-list.** *Verified, artifact-backed opt-out.* The affected path is HTTPS
   through the CF Tunnel, not SSH. `/hooks/infra-config-status` returned **HTTP 200 on all three
   verify attempts**, and the tunnel-borne root-SSH bootstrap completed its 9 post-write assertions
   in the same run. Both transports admitted traffic; no allow-list hypothesis survives.
2. **L3 — DNS / routing.** *Verified.* `deploy.soleur.ai` resolved and proxied to web-1; the
   handler exec is recorded on `host_name=soleur-web-platform`.
3. **L7 — TLS / proxy.** *Verified.* CF Access service-token handshake succeeded (200, not 403);
   `push-infra-config.sh` received its required HTTP 202.
4. **L7 — application.** *Verified, and causal.* `Reload daemon failed: Interactive authentication
   required.`

**Root cause (CONFIRMED):** the reload at `:415` runs as `User=deploy` (`webhook.service:16`) with
no sudoers grant and no polkit agent; `org.freedesktop.systemd1.reload-daemon` requires
`auth_admin`, so it returns non-zero and `set -e` aborts the handler mid-activation.

Residual UNKNOWNs, deliberately not graded:

- Whether `sync` (`:414`) ever contributes. Not observed failing; retained under the guard.
- Whether any *earlier* apply died at a different line. Untestable retroactively — no line number
  was ever recorded. That is the gap, not a question to answer by argument.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `app.soleur.ai/health` is 200 and
no user-facing surface is on this path. The exposure is second-order: this channel is the sole
no-SSH remediation route to the one host that cannot be replaced (`cx33`, 0/6 DC stock, ADR-154).

**If this leaks, the user's data is exposed via: a deploy→root escalation chain that this PR would
ACTIVATE.** The original draft called the grant "one non-mutating verb" and rated the threshold
`none`. That was wrong, and review caught it. Every link below is verified in-repo:

| Link | Status | Evidence |
|---|---|---|
| Write an arbitrary **full systemd unit** as root | **already granted** | `webhook.service` is a FILE_MAP dest at `644 root:root` — `infra-config-apply.sh:36`, `infra-config-install.sh:63` |
| …with **zero content validation** | **confirmed gap** | the env-file gate is scoped to `/etc/default/*` (`:160`) and the shape gate to `*.service.d/*.conf`. A bare `*.service` path matches **neither** |
| …invocable by `deploy` with any argv/stdin | **already granted** | `INFRA_CONFIG_INSTALL` is a **bare-command** alias (sudoers `:80-81`) |
| **Load** the rewritten unit | **← this PR would grant it** | `daemon-reload` |
| **Start** it as root | **already granted** | `WEBHOOK_SELF_RESTART` (sudoers `:30-31`) |
| Nothing re-narrows privilege downstream | **confirmed** | `webhook.service:18` — "`NoNewPrivileges` omitted" |

Today the write is **inert** — systemd never loads it and the next apply self-heals. The reload
grant is the missing link that makes it deterministic, immediate and self-service. And
`daemon-reload` takes **no unit argument**, so its scope is the entire systemd manager *by
construction*: exact-argv pinning buys nothing on the scope axis, only on the verb axis.

The installer's own comment is the tell (`infra-config-install.sh:172-173`): the unvalidated
`*.service.d/*.conf` dests were *"survivable only because nothing on this host root-restarted those
units, so an unvalidated drop-in sat inert on disk."* A **full unit** for `webhook.service` is a
strictly stronger write on a unit the deploy user can already root-restart — a case neither that
gate nor the `model.c4:431` invariant contemplated.

**Mitigation is blocking, not advisory:** AC-B1 extends the shape gate to
`/etc/systemd/system/*.service` before the grant ships (PR-B). Reaching prod is not a problem —
`infra-config-install.sh` is already in `triggers_replace` (`server.tf:1216`) and in the workflow
`paths:` filter.

**Brand-survival threshold:** `single-user incident` — a root compromise on the host that holds user
data. Raised from `none` after review; `requires_cpo_signoff: true` is set accordingly, and
`user-impact-reviewer` + `security-sentinel` must run at review time.

## Alternatives Considered (why widen privilege at all)

The original draft granted the reload without deriving why the cheaper options fail. That omission
is what made the grant look unmotivated. All four were weighed:

| Alternative | Verdict |
|---|---|
| **(a) Make the reload non-fatal (`\|\| true` + a degraded marker)** | **Reject.** The reconciliation loop still runs and still grades on *effect*, so a degraded run produces `restarted` verdicts on units that never re-read their config. Only safe if the marker also forces every RESTART_MAP entry to `failed/reload_denied` — at which point it *is* "fail loud", which the code already does |
| **(b) Drop the reload; rely on the granted `try-restart`** | **Reject — and it is the dangerous one.** systemd does **not** re-read unit files or drop-ins on `try-restart`; it warns and restarts from the in-memory unit. The grader at `:523-528` would then see `active` + an advanced `ExecMainStartTimestamp` and return `action=restarted, reason=stale_config` — a **manufactured false green inside the very mechanism ADR-159 built to end false greens**. Worse, the failure distribution splits: a pure credential *rotation* (`CRED_FILE` contents change, drop-in unchanged) **does** heal on a bare restart because `EnvironmentFile` is read at unit start, while the drop-in-shape case silently fails — same code path, same green verdict. **This is the load-bearing justification for widening privilege at all** |
| **(c) Move the reload into the root-SSH `remote-exec`** | **Reject.** Re-creates ADR-159's defect by construction — the no-SSH channel becomes delivery-only again — and makes every drop-in change depend on the bridge ADR-154 records as dead for 3 days on a host with 0/6 stock. Deviates from AP-002 (no SSH state mutation) and `hr-no-ssh-fallback-in-runbooks` |
| **(d) Reconcile inside `infra-config-install` (already root)** | **Reject, and ADR-159 already rejected it** — *"the installer is reachable through a bare-command grant that permits any arguments, and its own header records that the security boundary is therefore the helper, not sudoers."* The reasoning is **stronger** for reload: because `INFRA_CONFIG_INSTALL` is bare-command, a narrower `infra-config-install --daemon-reload` alias **cannot** be pinned — deploy can already pass any argv, so a reload mode inside the helper is an unconditional, ungated, on-demand root reload |

**Chosen:** the pinned alias (the plan's approach) — but only once AC-B1 closes the full-unit shape
gap, because (per `## User-Brand Impact`) the grant is what activates the escalation chain.

## Delivery split — two PRs

Review established that "the instrument ships before the fix" was an *authoring* order dressed as a
deployment one: both halves would land in one merge and one apply. Splitting makes it real, and the
split simultaneously de-risks both P0s. It also matches the issue's own framing — *"PRIMARY
DELIVERABLE (no production write required — do this first)."*

- **PR-A — the instrument.** Trap hoist, `errtrace`, pure-assignment ERR trap, `on_exit()` with ERR
  disarm + rc re-pin, `.fatal` handoff, real counters, gate message shape + `-replace` guardrail,
  `if: failure()` alert. **Zero privilege change, zero behaviour change.** It proves the reload
  denial *from the frame* on the very next apply — which is the issue's primary deliverable — and
  ships safely onto an unreplaceable host.
- **PR-B — the privilege.** The `*.service` shape-gate extension (AC-B1, blocking), the reload
  grant, seam reuse, the TEST_MODE guard split, self-restart hardening, the handler→grant lint, and
  the ADR/C4 edits. Lands with the instrument already live and reading.

PR-A does not fix the outage; PR-B does. That ordering is deliberate: PR-B touches a host that
cannot be rebuilt, and it should not be the first thing to exercise a brand-new fatal channel.

## Acceptance Criteria

### Pre-merge (PR)

**Privilege fix**

- **AC1** The reload routes through the **existing WRITE seam** — no third env var. `daemon-reload`
  and `try-restart` are the **same privilege domain** (root systemctl via sudo), so `:121-128` does
  not gain a third category; it gains a second granted argv inside its existing WRITE paragraph.
  Reuse `SYSTEMCTL_RESTART` (renamed `SYSTEMCTL_PRIV`, keeping the `INFRA_CONFIG_SYSTEMCTL` env name
  so the existing suite keeps working), invoked as `$SYSTEMCTL_PRIV daemon-reload`.
- **AC2** Verification is **derived from source on both sides**, extending
  `test_sudoers_caller_argv_lockstep` (`infra-config-apply.test.sh:1051`) — which already `sed`s the
  seam default out of the handler and asserts both provisioning paths grant identical argv. Assert
  `"${seam_default#sudo } daemon-reload"` is among the granted commands. Not a restated literal
  (`cq-assert-anchor-not-bare-token`). **Atomicity hazard:** that test greps the literal
  `SYSTEMCTL_RESTART="\${INFRA_CONFIG_SYSTEMCTL:-…}"`, so the rename must land in handler and test in
  one commit — otherwise the `sed` yields empty and the assertion compares against `""`.
- **AC3** Both sudoers sources carry the alias **and** its `deploy ALL=(root) NOPASSWD:` line.
  Assert with the suite's existing `^[[:space:]]*`-normalising comparison — **not** "byte-equivalent":
  the `cloud-init.yml` mirror is indented six spaces inside its YAML block, and the existing parity
  test normalises for exactly that reason (`infra-config-apply.test.sh:666-667`, `:1060`).
- **AC4** `terraform_data.infra_config_handler_bootstrap`'s `remote-exec` asserts the grant is
  **effective**, not merely present, using a real policy probe:
  `sudo -n -l /usr/bin/systemctl daemon-reload`. Strictly better than the existing name-only
  `grep -q INFRA_CONFIG_INSTALL` precedent, which a `Cmnd_Alias` defined but never granted to
  `deploy` would pass — and the sudoers file itself already records (`:93-94`) that argv is coupled
  to the caller and pinned by a test, not by a grep. Closes AC2 on-host rather than by review.
- **AC5** The reload call is lifted **out** of the `if [[ -z "${INFRA_CONFIG_TEST_MODE:-}" ]]` guard
  at `:413-416`; `sync` stays inside it. Without this the reload arms below execute **zero lines of
  the code they claim to cover** and register as passing — the identical construction this bug is
  made of. Mirrors the precedent the handler's own comment sets at `:409-412`.
- **AC6 (class closure) — handler→grant lint** in `infra-config-apply.test.sh`, scoped to
  `infra-config-apply.sh` only: derive every `systemctl`/`systemd-run` invocation, classify the verb
  against an explicit READ allowlist (`show`, `is-active`, `is-enabled`, `cat`, `status`,
  `list-units`), and assert every non-READ verb is `sudo`-prefixed **and** its resolved argv appears
  in a `Cmnd_Alias` in **both** sudoers sources. Fail closed if zero invocations are derived
  (vacuity guard, mirroring `:711`). **Must be proven RED against `main`** — the only proof it would
  have caught #7220. Existing guards run grant→handler (`:1051`, derived from `RESTART_MAP`) and
  source→source, so neither can **structurally** see a bare non-sudo verb at `:415`.

- **AC-B1 (P0, blocks the grant)** `infra-config-install.sh`'s content gate is extended to cover
  `/etc/systemd/system/*.service` dests — the full-unit case that today matches **neither** the
  `/etc/default/*` env-file gate (`:160`) nor the `*.service.d/*.conf` drop-in gate. A content pin
  (digest) is the right shape: you cannot forbid `ExecStart=` on a full unit, so a permitted-directive
  grammar is the wrong tool. Alternative accepted only if pinning proves infeasible: drop
  `/etc/systemd/system/webhook.service` from `FILE_MAP`/`DEST_SPEC` — but note that costs the **only**
  delivery path to a running host (`server.tf:1422` is a `triggers_replace` hash input;
  `cloud-init.yml:239` is create-time under `ignore_changes=[user_data]`). **This AC must land before
  or with the reload grant, never after.**
- **AC-B2 (P0, self-restart hardening)** The delayed webhook self-restart at `:586` has **never
  executed in production** — `fc8b81796` shipped it *after* the reload in the same `set -e` block, so
  it has been unreachable since May 2026, with zero test coverage (`INFRA_CONFIG_TEST_MODE` gates it
  out at `:582`). Re-enabling a never-once-run root-restart path on an unreplaceable host requires:
  1. **`hooks.json` self-wedge guard.** The orphan sweep (`:390-401`) is `command -v jq`-guarded and
     `|| true`-suffixed, so a *syntactically invalid* `hooks.json` passes delivery silently and would
     now activate 3 s later. adnanh/webhook with `-verbose` does not abort on an unparseable hooks
     file — it comes up **serving zero hooks**. The port answers, so the verify's `000/502/503`
     "listener is DOWN" branch never fires and the **404** branch fires with remediation text pointing
     at "first bootstrap" — the wrong diagnosis, on the channel needed to repair it. Make the sweep's
     `jq` parse failure a hard per-file failure rather than a silent pass.
  2. **`--collect`** on the `systemd-run` transient unit. `--unit=webhook-self-restart` is a fixed
     name; a transient unit that *fails* is not garbage-collected, so the next apply's `systemd-run`
     fails "unit already exists" permanently and silently. Adding `--collect` **changes the argv** and
     therefore requires updating `WEBHOOK_SELF_RESTART` in **both** sudoers copies in lockstep
     (`deploy-inngest-bootstrap.sudoers:30`, `cloud-init.yml:90`) or the self-restart becomes denied.
  3. **`StartLimitIntervalSec=0`** in `webhook.service`'s `[Unit]`. It sets `Restart=on-failure` /
     `RestartSec=5` with no start-limit override (zero hits repo-wide), so systemd's default 5-in-10s
     applies; the first post-merge apply performs two restarts in quick succession
     (`server.tf:1301` synchronous, then the handler's). Blowing the limit leaves webhook `failed`
     needing `systemctl reset-failed` — i.e. SSH.
- **AC-B3 (frame blind spot)** `touch "${STATE_FILE}.final"` at `:549` **precedes** the self-restart
  at `:586`, so any failure there leaves the EXIT trap seeing `.final` and *not* rewriting the frame:
  the frame reads `exit_code:0` while the process exits non-zero, and CI reads green. The journald arm
  still emits, but the frame arm cannot — the dual channel silently degrades to single **exactly in
  the region being re-enabled**. Either move the `.final` touch after the self-restart, or have the
  fatal path rewrite the frame even when `.final` exists.
- **AC-B4 (activation, not just reload)** `inngest-heartbeat.service.d/10-…conf` and
  `inngest-server.service.d/10-…conf` are in `FILE_MAP` but in **neither** `RESTART_MAP` nor the
  grant set — their *entire* activation story is the daemon-reload. If those units exist on web-1
  they have been running the pre-#7095 (revoked) credential ever since. Assert
  `systemctl show -p DropInPaths` on both post-reload. This is the difference between "we fixed
  reload" and "we fixed what reload was for."

**Fatal-error channel**

- **AC7** Traps and state-file handling are **hoisted above the `exit 64` guard**. Today `START_TS`
  (`:196`), `rm -f "$STATE_FILE"` (`:208`) and the EXIT trap (`:221`) all sit *below* the
  `RESTART_SETTLE_SECS` guard at `:146-150`. A non-numeric env value therefore `exit 64`s while the
  **previous** run's frame is still on disk — and the gate reads no timestamp, so a stale *green*
  frame certifies an apply that delivered nothing. The handler's own comment at `:143-145` says that
  path is reachable in practice. Install the ERR + EXIT traps immediately after `LOG_TAG` (`:19`)
  and move `START_TS`/`rm` above the guard, so `exit 64` produces a real frame with `fatal_rc=64`.
- **AC8** The `ERR` trap is **pure assignment** —
  `trap 'FATAL_RC=$?; FATAL_LINE=$LINENO; FATAL_CMD=$BASH_COMMAND; …' ERR` with `set -o errtrace`.
  No `logger`, no subshell, no sanitizer inside it. All emission happens in the EXIT trap, which
  already runs only when `rc != 0`. This makes a false `SOLEUR_INFRA_CONFIG_FATAL` **structurally
  impossible** rather than test-verified. The single quotes are load-bearing — double quotes expand
  at *definition* time and silently pin the trap's own line forever. Require an inline comment.
- **AC9** The trap hands the triple over through **`"$STATE_FILE.fatal"`**, not variables. A failure
  inside a subshell assigns in the child and the parent's EXIT trap would otherwise write a frame
  with no attribution — while the plan claims the frame is the transport-independent arm. A file
  crosses the process boundary; a variable does not. Test arm: force a fatal inside `$( )` and
  assert `fatal_line` still reaches the frame.
- **AC10 (P0)** The EXIT trap becomes a named `on_exit()` that, **in this order**: captures
  `rc=$?`; runs `trap - ERR` as its first statement; does all work with `|| true`; and re-pins the
  original status. **Measured:** a failing command inside an armed EXIT trap both fires ERR and
  turns `exit 0` into rc=1 — and `trap - ERR` alone suppresses only the marker, not the status flip.
  Without this, enriching the trap can **turn a green apply red on the host with no SSH runbook** —
  the instrument becoming the outage. **AC: a clean apply exits 0 with the enriched trap in place.**
- **AC11** `cmd` is sanitized in `on_exit` with the **existing** `r_err_safe` idiom (`:497`):
  `tr -d '\000-\037' | tr -c 'A-Za-z0-9 ._:/=-' '?' | cut -c1-200`. That charset excludes `"` and
  `\`, which is what keeps the frame valid JSON by construction — state this, it is load-bearing.
  Assert the emitted line carries no newline and no raw quote, **and** add a fixture where the
  failing command references a secret-bearing variable, asserting the **value** never reaches
  `$LOGGER_LOG` or the frame.
- **AC12** The frame emits `fatal_rc`/`fatal_line`/`fatal_cmd` **unconditionally**, zeroed when ERR
  never fired. One branchless `printf` makes "valid JSON in both cases" true by construction.
- **AC13** Real accounting — a three-token substitution in the trap's `printf` args: `0 0 0` →
  `"${WRITTEN_COUNT:-0}" "${FAIL_COUNT:-0}" "${TOTAL_COUNT:-0}"`. **The `:-0` defaults are
  mandatory** (measured, §(c)): the trap is installed above `WRITTEN_COUNT=0` (`:240`), and a bare
  `$WRITTEN_COUNT` makes an abort in that window write **no frame at all** — which
  `cat-infra-config-state.sh:13` then reports as `no_prior_apply`, i.e. "the handler never ran". AC:
  an abort *before* the counters are initialised still produces a well-formed frame.
  **No `accounting:` enum.** `files_total == 0` iff the trap fired before `:236`, and `FILE_MAP` is
  a 19-entry literal that is never empty — the enum would be a second source of truth for a fact the
  frame already carries, and it could not even express the #7220 shape (19/19 written *then* abort
  is neither `none` nor `partial`). Cutting it dissolves that defect rather than fixing it.
- **AC14** The reload-**success** positive control asserts both that `SOLEUR_INFRA_CONFIG_RESTART`
  is emitted **and** that **zero** `SOLEUR_INFRA_CONFIG_FATAL` markers appear in `$LOGGER_LOG`. The
  second half is the only executable mitigation for the plan's biggest behavioural risk. Both reload
  arms carry a non-vacuity assertion proving the seam stub was actually invoked (mirroring the
  `n_matched >= 1` guard at `:1085-1090`).

**Operator-facing output**

- **AC15** The gate's fatal `::error::` is asserted by its **rendered text**, verified by a gate test
  arm fed a synthetic frame with `fatal_line=415`. A `grep -c 'fatal_line' … ≥ 1` is satisfied by a
  comment — the exact `cq-assert-anchor-not-bare-token` violation. The message MUST contain:
  1. `infra-config-apply.sh:<line>` and the sanitized command;
  2. **"every step after this line did not run"** — what turns a line number into a mental model;
  3. **what is still true**: `files_written=N of M delivered`, so a red gate is not misread as
     "config never reached the host";
  4. the copy-pasteable next command using **`--since 1h`**, never an absolute timestamp (verified
     supported: the `^([0-9]+)([hmd])$ → INTERVAL` branch, `betterstack-query.sh:165`);
  5. **the `-replace` guardrail**, verbatim: *"This does NOT mean the host is bricked. Do NOT run
     `terraform apply -replace` — that lever is only for a status endpoint returning 000/502/503,
     and this host cannot be re-provisioned (`cx33`, 0/6 stock)."*
     **Highest-value line in the change.** The last incident's annotation was two-thirds false and
     the issue written from it pointed at `-replace` on an unreplaceable host. The next incident
     reads the annotation, not this plan.
- **AC16** The count branches (`infra-config-gate.sh:193`, `:197`) and the per-unit
  activation-contract branch are suppressed on a frame carrying `fatal_line`, which already explains
  why there is no verdict. Prevents the abort frame emitting one misleading `::error::` per unit.
- **AC17 (P0)** A red infra-config gate **notifies someone**. Today the workflow's only alerting
  mechanism, `seccomp_unenforced_alert` (files a plain-language GitHub issue **and** a Sentry event;
  the reason the workflow holds `permissions: issues: write` at `:166`), sits inside an
  `if: success()` step (`:641`) and therefore **never runs when this gate reds**. A `::error::` is a
  log line in a run nobody is paged on. Add an `if: failure()` step on the gate path reusing that
  proven pattern, and correct the Observability block's `alert_route`. For a non-technical founder
  on the sole no-SSH channel, this is the difference between a diagnosis and a dead end.

**Exit gate**

- **AC18** `bash apps/web-platform/infra/run-registered-suites.sh` is green, invoked via its own
  entry point — not a hand-enumerated file list. (Verified genuinely the gate: the runner derives
  its list from `infra-validation.yml` and cross-checks `git ls-files`, `:116`/`:150`.)

### Post-merge (automatic — no operator step)

- **AC19** The merge fires `apply-deploy-pipeline-fix.yml` (path filter verified to cover both
  `infra-config-apply.sh` and `deploy-inngest-bootstrap.sudoers`, `:72-73`), replacing
  `terraform_data.infra_config_handler_bootstrap` over root SSH and re-firing `push-infra-config.sh`.
  **Automation: fully automated** — the same path that ran successfully at 11:58:30Z in the failing
  run.
- **AC20** The verify step passes with `exit_code=0`, `files_written=19`, `files_total=19`, and a
  `restarts[]` entry for `vector.service`. **Plus a `start_ts` freshness pin**: `start_ts` must
  postdate the workflow's apply start. Without it the AC asserts a **proxy** — every one of those
  values is satisfiable by a *stale* frame, so it would prove "some apply reconciled", not "this one
  did". Precedent in-repo: `scripts/followthroughs/ac12-telemetry-positive-control-7103.sh` reads
  `start_ts` from this exact endpoint as its Guard 1.
- **AC21 (ship-blocking if omitted)** AC20's soak is **enrolled**, not remembered. Write
  `scripts/followthroughs/infra-config-activation-7220.sh` asserting ≥1
  `SOLEUR_INFRA_CONFIG_RESTART` for `vector.service` (field-isolated on `SYSLOG_IDENTIFIER` from the
  JSON `raw` column, per the #6475 learning — never a bare substring) and **zero**
  `SOLEUR_INFRA_CONFIG_FATAL`, plus the elapsed-time guard. Add the
  `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive and the `follow-through`
  label. `.claude/hooks/ship-soak-followthrough-gate.sh` is a PreToolUse hook that **denies
  `gh pr ready` / `gh pr merge --auto`** without it, so this is a hard stop at ship, not a nicety.
  Template: `plugins/soleur/skills/ship/references/followthrough-stub-template.sh`; the
  `BETTERSTACK_QUERY_*` secrets are already wired into `scheduled-followthrough-sweeper.yml`.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INFRA_CONFIG_RESTART (one row per RESTART_MAP unit, emitted unconditionally)
  cadence: once per infra-config apply (per merge touching a managed file)
  alert_target: the apply-deploy-pipeline-fix.yml verify step (fails the workflow) PLUS the new
    if: failure() alert (AC17) which files a plain-language GitHub issue + a Sentry event
  configured_in: apps/web-platform/infra/infra-config-apply.sh:537 + vector.toml Source 4 (already allowlisted)

error_reporting:
  destination: DUAL, and asymmetric — say so rather than implying symmetry:
    (a) journald -> Vector -> Better Stack (SOLEUR_INFRA_CONFIG_FATAL). Survives a lost state file.
    (b) the state frame, served over HTTPS by /hooks/infra-config-status and already polled by CI
        (fatal_line/fatal_cmd/fatal_rc). Survives a dead journald transport. Requires the
        "$STATE_FILE.fatal" handoff (AC9) to survive a subshell fatal.
  fail_loud: true — the handler keeps set -e and a non-zero exit; the ERR trap adds attribution,
    it does not swallow. The EXIT trap disarms ERR and re-pins rc so the instrument can never
    convert a green apply into a red one (AC10).

failure_modes:
  - mode: privileged systemd verb denied to the deploy user (the #7220 cause)
    detection: fatal_line pointing at the call + fatal_cmd carrying the denial text
    alert_route: gate ::error:: (AC15) + the if: failure() issue/Sentry alert (AC17)
  - mode: handler dies at any other line under set -e
    detection: same fields, different line= — the general case the channel buys
    alert_route: same
  - mode: handler never exec'd (E2BIG / dangling hook, the #6178 shape)
    detection: NOT no_prior_apply — the rm at :208 lives INSIDE the handler, so a handler that
      never starts leaves the PREVIOUS frame served verbatim, and it can read green. The
      discriminator is the AC20 start_ts freshness pin, not the reason field.
    alert_route: gate ::error:: + AC17 alert
  - mode: bad env value trips the exit 64 guard
    detection: post-AC7 this produces a real frame with fatal_rc=64; before AC7 it served a stale
      frame and could certify a delivery that never happened
    alert_route: same
  - mode: handler completed but failed to publish its frame
    detection: currently indistinguishable from "never ran" (-2), because `.final` is touched at
      :549 BEFORE the mktemp/printf/mv at :550-568 and all three arms are guarded. Move the
      `.final` touch to AFTER a successful mv so this state stops collapsing into (a).
    alert_route: same

logs:
  where: Better Stack Logs source 2457081 (host_name=soleur-web-platform), read-only via
    scripts/betterstack-query.sh; plus the HTTPS status endpoint
  retention: the existing source's hot window (~40 min) + the S3 archive arm

discoverability_test:
  command: >-
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    --since 1h --grep SOLEUR_INFRA_CONFIG_FATAL --limit 20
  expected_output: >-
    zero rows on a healthy apply (negative control); on a fatal, one row carrying rc=, line= and a
    sanitized cmd=. NO ssh anywhere in the path. `--since 1h` is deliberate: the relative form needs
    no clock arithmetic and sidesteps the script's ISO papercut (its header advertises "ISO" but the
    canonical Z-suffixed form is pasted verbatim into SQL and rejected by ClickHouse — measured
    in-session; filed as a follow-up, not fixed here).
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-159** (`delivery-is-not-activation`) — do **not** mint a new ordinal. ADR-159 already
owns "a config channel must reconcile the units it configures"; #7220 shows its decision was
unexecutable as shipped. Add to its `## Decision`:

> Activation requires **privilege**, not just code. Every privileged systemd verb the handler
> invokes as `User=deploy` must route through an exact-argv sudoers alias, and a lint must assert
> that in the handler→grant direction — the grant→handler guards that existed could not see a bare
> non-sudo verb at all. Note the taxonomy at `infra-config-apply.sh:121-128` is by **privilege
> domain**, not by verb: `daemon-reload` is a WRITE alongside `try-restart`, not a third category.
> And a *load* grant is not a weaker *restart* grant: `daemon-reload` takes no unit, so its scope is
> the whole manager, and it is the link that converts an arbitrary root **write** the deploy user
> already holds into an arbitrary root **execution**. Widening it requires the write side to be
> content-gated first.

**Also amend `## Consequences` — #7220 falsifies a clause standing there today:**

> "The grant bought nothing either, because a timer-driven oneshot re-reads its drop-in on its next
> tick **after the `daemon-reload` the handler already performs**."

The handler has **never** performed it. ADR-159's stated basis for removing the `inngest-heartbeat`
restart grant was therefore false when written, and its concluding general rule ("for some unit
types, daemon-reload plus the next scheduled start is the activation") rested on a capability the
system did not have. The same premise is duplicated in **three** places, all of which must be
corrected together: `infra-config-apply.sh:106-108`, `deploy-inngest-bootstrap.sudoers:118-123`, and
ADR-159 `## Consequences`.

Record three corollaries: the abort frame's `files_total:0` sentinel actively misreported a complete
delivery as a zero delivery, so an abort frame must carry attribution rather than just a non-zero
rc; alternative (d) — reconciling inside `infra-config-install` — stays rejected for the reason
ADR-159 already gives, and *more* strongly for reload (a bare-command grant cannot be narrowed by a
sub-alias); and the reason this activation path carries so much ceremony is that `-replace` is not a
real lever while the host is a `cx33` at 0/6 stock (ADR-154) — hardening the channel is treating the
symptom of an unreplaceable host.

### C4 views

**One edit, in `model.c4` only.** The `tunnel -> hetzner` edge description (`model.c4:431`) asserts:

> "The handler now restarts the units it configures and reports a per-unit verdict the CI gate
> adjudicates"

**Falsified** — the handler dies before the restart loop and `restarts[]` ships empty. Correct it to
state the reconciliation is gated on the reload grant, and that the per-unit verdict became real
only once that grant existed.

**Second, larger edit to the same description — do not skip it.** That sentence also carries the
delivery↔activation *invariant*, and it names `DROPIN_TRY_RESTART` specifically. Extend it to (i)
name reload as the **load** step of write→load→execute, and (ii) record that the shape gate did not
cover `/etc/systemd/system/webhook.service` until AC-B1. Leaving the invariant naming only the
restart grant reproduces the exact reasoning gap that let the escalation chain through review —
the gate's own safety argument (`infra-config-install.sh:193-199`) turns on *"both units the grant
covers run `User=deploy` … lateral, not escalation"*, and its escape clause (`:201-202`) is keyed on
"a future unit running as root is added to RESTART_MAP" — the **wrong register**. The hazard is
"the deploy user can root-restart it", not "it is in RESTART_MAP".

**Enumeration behind "no new elements"** (all three `.c4` files read): no external human actor added
(the operator is unchanged); no external system added (`betterstack`, `sentry` already modeled at
`:287`/`:296`); no container or data store added; and the sudoers grant is a **host-internal**
privilege boundary between `deploy` and root, below C4 container granularity and already described
in prose on the same edge. `views.c4` and `spec.c4` therefore unchanged (no new element to
`include`). Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — the `sudo -l -U deploy` post-write assertion (AC4). No new
  resource, provider, or variable, and **no new `TF_VAR_*`** — no operator mint, no
  `hr-tf-variable-no-operator-mint-default` exposure.
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — the grant. **This file is** an input
  to `triggers_replace` (`server.tf:1214-1220`).
- `apps/web-platform/infra/cloud-init.yml` — the mirror. **Correction:** `cloud-init.yml` is **not**
  in `triggers_replace` (that list is `infra-config-apply.sh`, `infra-config-install.sh`,
  `deploy-inngest-bootstrap.sudoers`, `cat-infra-config-state.sh`, `local.hooks_json`). Harmless
  here — the sudoers file is co-edited and cloud-init governs only fresh hosts — but a
  cloud-init-only edit does **not** auto-apply, and a future reader must not assume it does.

### Apply path

**(b) cloud-init + idempotent bootstrap**, already wired. Editing `infra-config-apply.sh` or the
sudoers file changes `terraform_data.infra_config_handler_bootstrap.triggers_replace`
(`server.tf:1215`), so the merge-triggered workflow replaces the resource, re-delivers over root SSH
through the CF Tunnel, and re-fires `push-infra-config.sh`.

Blast radius: the resource's `remote-exec` performs a synchronous webhook restart
(`server.tf:1301`) — a sub-second management-plane blip. `app.soleur.ai` does not traverse this
path. User-visible downtime: **none**.

**No operator-gated `terraform apply -replace` is required** — see `## Operator-Gated`.

### Distinctness / drift safeguards

- The sudoers content exists in two places; AC3 pins both with the suite's normalising comparison.
- `visudo -cf` validates **syntax** at delivery (`server.tf:1297-1299`) — never policy. Policy is
  AC2's derived argv lockstep and AC4's on-host `sudo -l` check.
- No secret value is added; nothing new lands in `terraform.tfstate`.

### Vendor-tier reality check

Not applicable — no vendor resource is created. The new marker rides an already-allowlisted
identifier on the existing Better Stack source; the healthy path emits nothing, so the quota delta
is a handful of rows on failure only.

## Encryption Posture

**Skipped — detection did not fire.** No persistent store and no new cross-component connection.
`server.tf` is edited only to add an assertion inside an existing `remote-exec`; no volume, bucket,
table, queue, cache or backup target is declared, and no new network edge is opened. The one
transport touched (journald → Vector → Better Stack over HTTPS) already exists and is unchanged.

One posture-adjacent constraint, carried into AC11: `BASH_COMMAND` can *name*
`/etc/default/soleur-doppler-token`, and the file's **contents** must never reach journald — the
same reasoning that made `:326` forbid `diff`/`od` on a FILE_MAP dest. Emitting the command text is
safe; emitting anything read from the file is not, and AC11 now has a fixture asserting exactly that.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` returned
no body containing `infra-config-apply.sh`, `infra-config-gate.sh`, `deploy-inngest-bootstrap.sudoers`
or `vector.toml`.

## Implementation Phases

### Phase 0 — Preconditions (no edits, both PRs)

0.1 Re-run `scratchpad/errtrap.sh` + `scratchpad/p0verify.sh` on **the target image's** bash
    (Ubuntu 24.04 / 5.2.x), not CI's. The measurements in this plan are from 5.3.9.
0.2 Read `infra-config-apply.test.sh:401` (`test_exit_trap_unhandled`), `:634`
    (`test_dropin_restart_grant`), `:1051` (`test_sudoers_caller_argv_lockstep`) — most new
    assertions are **extensions of these**, not new registered functions. Note
    `test_exit_trap_unhandled` aborts *inside* the write loop, so it cannot cover the
    abort-before-counters case in AC13; that one needs a new arm.

---

### PR-A — the instrument (no privilege change, no behaviour change)

**A1** Hoist `START_TS`, the state-file `rm`s, and both traps above the `exit 64` guard (AC7).
**A2** `set -o errtrace` + the pure-assignment ERR trap writing `"$STATE_FILE.fatal"` (AC8, AC9).
**A3** Convert the EXIT trap to `on_exit()`: capture `rc`, `trap - ERR` **first**, all work
`|| true`, re-pin the status (AC10). Sanitize with the `:497` idiom (AC11).
**A4** Unconditional zeroed `fatal_*` + real counters with mandatory `${VAR:-0}` (AC12, AC13).
**A5** Move the `.final` touch after a successful `mv` so "completed but frame-publish failed" stops
collapsing into "never ran" (also the first half of AC-B3).
**A6** Gate message shape incl. the `-replace` guardrail (AC15) + branch suppression (AC16); gate
test arms fed synthetic frames.
**A7** `if: failure()` alert step in `apply-deploy-pipeline-fix.yml` reusing
`seccomp_unenforced_alert` (AC17).
**A8** Tests: subshell-fatal arm, abort-before-counters arm, secret-value sanitization fixture,
clean-apply-exits-0 arm.
**A9** Exit gate: `run-registered-suites.sh`, then `scripts/test-all.sh`.

*Expected outcome on merge: the next apply still fails — but the frame and the annotation now name
`infra-config-apply.sh:415` and the denial text. That is the issue's primary deliverable, and it
independently re-confirms the root cause from a second, orthogonal instrument.*

---

### PR-B — the privilege (opens only after PR-A is live and reading)

**B1 (blocking, first)** Extend `infra-config-install.sh`'s content gate to
`/etc/systemd/system/*.service` (AC-B1). **Nothing else in PR-B may merge ahead of this.**
**B2** Sudoers alias + `deploy ALL=(root) NOPASSWD:` line in `deploy-inngest-bootstrap.sudoers` and
the `cloud-init.yml` mirror.
**B3** Rename `SYSTEMCTL_RESTART` → `SYSTEMCTL_PRIV` (env name unchanged) **atomically with**
`test_sudoers_caller_argv_lockstep`'s `sed` pattern; update the `:121-128` WRITE paragraph.
**B4** Split `:413-416`: `sync` stays guarded, the seamed reload moves out (AC5).
**B5** Self-restart hardening (AC-B2): hard-fail the `jq` parse in the orphan sweep, `--collect` on
the transient unit **with the lockstep sudoers argv update in both copies**, and
`StartLimitIntervalSec=0` in `webhook.service`.
**B6** `server.tf` `sudo -n -l` policy probe (AC4) + the `DropInPaths` assertion for the two
drop-in-only units (AC-B4).
**B7** Tests: extend the two existing sudoers tests; the reload-denied arm and the reload-success
positive control (one verb-dispatching stub, `case "$1" in`), both with non-vacuity assertions and
the zero-fatal-markers assertion (AC14).
**B8** The handler→grant lint (AC6), proven RED against `main`.
**B9** Amend ADR-159 (`## Decision` **and** the falsified `## Consequences` clause, plus the two
duplicate sites); correct `model.c4:431` including the invariant text; run the two C4 tests.
**B10** `start_ts` freshness pin (AC20) + the enrolled follow-through probe (AC21).
**B11** Exit gate: `run-registered-suites.sh`, then `scripts/test-all.sh`.

## Operator-Gated — DEFERRED, and it is NOT needed

The issue prescribes `terraform apply -replace=terraform_data.infra_config_handler_bootstrap`.
**This plan does not execute it, and the evidence says it is not required.**

That lever is for a *bricked webhook listener* — the `000/502/503` branch at
`apply-deploy-pipeline-fix.yml:631`. The measured state is the opposite:

- `/hooks/infra-config-status` returned **HTTP 200** on all three attempts.
- `terraform_data.infra_config_handler_bootstrap` was **replaced successfully in the failing run**,
  including its root-SSH webhook restart and all 9 post-write assertions.
- The handler that ran was the new one (`schema_version:2`), so SSH delivery demonstrably works.

The fix reaches prod through the **normal merge path** (AC19). No production write, no
`-auto-approve`, and no `hr-menu-option-ack-not-prod-write-auth` authorisation is sought.

**If** a future apply shows the listener genuinely unreachable (`000/502/503`), `-replace` becomes
the correct escalation — and per `hr-menu-option-ack-not-prod-write-auth` it then requires explicit
operator authorisation plus Terraform's own interactive `yes`, never `-auto-approve`, on a host that
cannot be replaced (`cx33`, 0/6 DC stock, ADR-154). AC15's guardrail exists so the operator is told
this **in the annotation**, at the moment they would otherwise reach for it.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The instrument becomes the outage** — an enriched EXIT trap flips a green apply red on the host with no SSH runbook | AC10, measured: `trap - ERR` first + `\|\| true` on every command + re-pin `rc`, with an AC asserting a clean apply exits 0. `trap - ERR` alone is insufficient |
| **The instrument silences itself** — an unset counter under `set -u` makes the trap write no frame at all | AC13's mandatory `${VAR:-0}`, measured; plus an abort-before-counters test arm |
| A stale frame certifies an apply that never happened | AC7 (traps above the `exit 64` guard) + AC20's `start_ts` freshness pin. The count/content/restarts invariants are all satisfiable by a stale frame |
| **The grant activates a latent deploy→root escalation chain** (arbitrary root unit write → load → root start) | **AC-B1 is blocking**: the `*.service` content gate ships before/with the grant. Plus exact-argv alias, `visudo -cf`, AC2's derived lockstep, AC4's `sudo -n -l` policy probe, AC6's class lint, and mandatory `security-sentinel` + `user-impact-reviewer` at the raised threshold. Note exact-argv pinning buys **nothing** on the scope axis here — `daemon-reload` takes no unit |
| **Re-enabling a root-restart path that has never once executed in production** (May 2026 → today, zero runs, zero test coverage) | AC-B2's four-part hardening: hooks.json parse hard-fail, `--collect` (with the lockstep sudoers argv update), `StartLimitIntervalSec=0`, and the PR-A/PR-B split so the instrument is already live when it first fires |
| A self-restart failure is invisible to the frame (`.final` touched before it) | AC-B3 / A5 — move the touch after a successful `mv`, or rewrite the frame on the fatal path even when `.final` exists. Otherwise the dual channel degrades to journald-only exactly where it is being re-enabled, and CI reads green |
| The two drop-in-only units may have been running a revoked credential since #7095 | AC-B4's `DropInPaths` assertion. Not "out of scope" — their entire activation story *is* the reload being repaired |
| The reload arms test a branch that is gated out | AC5 splits the TEST_MODE guard; both arms carry non-vacuity assertions |
| False fatal markers on a healthy run | Structurally impossible via the pure-assignment ERR trap (AC8), plus AC14's explicit zero-marker assertion. Measured clean against all five guarded idioms |
| Reusing one seam for two verbs means a stub can't discriminate | One stub dispatching on `$1`; this is *stronger* than two seams because it proves the handler sends the right verb to the right place |
| Re-enabling the long-dark webhook self-restart path | It has been skipped since the reload started failing (~May 2026). It is `systemd-run --on-active=3s`, already granted and unchanged; AC20's post-apply verdict is the check that it lands |
| A different line aborts the next apply | The channel names it. This is the general case the instrument buys, independent of #7220's cause |

## Non-Goals

- `soleur-web-2`'s `IMAGE_PULL_FAIL … auth_denied` on `v0.248.2` — pre-existing B4 on open tracker
  **#7103**, re-confirmed live today. Not widened into.
- Any change to `vector.toml` or the Source 4 allowlist. The marker rides an already-allowlisted
  identifier; no allowlist edit is needed. *(The journald R1-1.8a/b/c triad was cut: it is feasible
  and cheap, but it guards a file this PR does not touch against a regression this PR cannot
  introduce. Dissent recorded — one reviewer rated it near-zero-cost boilerplate worth keeping.)*
- Any change to `FILE_MAP`, `hooks.json.tmpl`, or `push-infra-config.sh` — the 19-entry contract is
  verified aligned and is not the defect.
- Retroactive attribution of pre-#7146 applies. No line numbers were ever recorded.
- **Deferred to follow-up issues** (file during `/work`): (a) the `betterstack-query.sh --since` ISO
  papercut — its header advertises "ISO" while the canonical `Z`-suffixed form is rejected, a false
  statement on the incident path; AC15's `--since 1h` removes it from every command this PR
  prescribes, which is why it does not gate here. (b) Extracting a shared `infra-fatal-trap.sh` —
  this is now the **fourth** bespoke fatal trap (`ci-deploy.sh:471` is stderr-only with no
  `errtrace` and a non-`SOLEUR_*` marker, so its fatal line never leaves the host).
  (c) Restoring `-replace` as a real lever (second web host / instance type) per ADR-154.

## Plan Review Revisions (6-agent panel)

Every item below was found by review, not by the original draft. Recorded because three of them
would have made the change *worse than the bug*.

| # | Finding | Disposition |
|---|---|---|
| R1 | **The reload grant activates a latent deploy→root escalation chain**; threshold was wrongly rated `none` | Threshold raised to `single-user incident`; AC-B1 shape gate made blocking; chain documented with per-link evidence |
| R2 | **The ERR trap stays armed during the EXIT trap** — enriching that trap could turn a *green* apply red on an unreplaceable host (measured: `exit 0` → rc=1) | AC10: `trap - ERR` first + `\|\| true` + rc re-pin. Found that `trap - ERR` alone is insufficient |
| R3 | **`${VAR:-0}` is mandatory** — an EXIT trap expanding an unset var under `set -u` writes **no frame at all**, and `2>/dev/null \|\| true` does not save it (measured) | AC13 + an abort-before-counters test arm |
| R4 | The self-restart has **never executed in production** (not "skipped recently") — zero runs since May 2026, zero test coverage | AC-B2's four-part hardening + the PR split |
| R5 | `failure_modes` claimed "handler never exec'd → `no_prior_apply`" — **false**; the `rm` is *inside* the handler, so a stale (possibly green) frame is served | Corrected; AC7 hoist + AC20 `start_ts` freshness pin |
| R6 | A red gate **notifies no one** — the workflow's only alerting path is inside an `if: success()` step | AC17 `if: failure()` alert |
| R7 | The annotation must carry the **do-not-`-replace` guardrail**; the last one misdirected the operator | AC15, rated the highest-value line in the change |
| R8 | AC10 as drafted was LARP (`grep -c` satisfied by a comment) — the very class it cited | Rewritten to assert rendered text |
| R9 | `accounting:` enum was derivable, and could not express #7220's own shape | **Cut** — dissolves the defect rather than fixing it |
| R10 | A third seam was unnecessary; `daemon-reload` is the same privilege domain as `try-restart` | Reuse the WRITE seam; ADR taxonomy correction |
| R11 | AC12's reload arms were unimplementable (branch gated out by `INFRA_CONFIG_TEST_MODE`) | AC5 splits the guard; non-vacuity assertions added |
| R12 | Alternatives (a)-(d) were never derived — notably that `try-restart` **does not** re-read drop-ins, so relying on it would manufacture a false green | `## Alternatives Considered` added; (b) is the load-bearing justification |
| R13 | ADR-159's `## Consequences` contains a clause #7220 falsifies, duplicated in 3 places | Amendment scope extended to all three |
| R14 | AC3's "byte-equivalent" contradicted the suite it delegates to (the mirror is indented) | Reworded to the suite's normalising comparison |
| R15 | The IaC section falsely claimed `cloud-init.yml` is in `triggers_replace` | Corrected |
| R16 | Subshell fatals lose the `FATAL_*` triple | AC9's `"$STATE_FILE.fatal"` handoff |
| R17 | AC18's soak would **block `gh pr ready`** without an enrolled follow-through | AC21 enrollment |
| R18 | Counting ACs used bare `grep -c`, which exits 1 on zero matches (aborts the passing case), and `git diff origin/main` is the wrong two-dot range | Rewritten; AC on `vector.toml` cut as duplicate of Non-Goals |
| R19 | Phase count / instrument-first doctrine was ceremony in a single PR | Collapsed; the **PR-A/PR-B split** makes the ordering real |
| R20 | Journald R1-1.8a/b/c triad guards an untouched file | Cut, dissent recorded in Non-Goals |

## Domain Review

**Domains relevant:** Engineering

> **CPO sign-off required at plan time** (`brand_survival_threshold: single-user incident`, raised at
> review). `user-impact-reviewer` and `security-sentinel` are mandatory at review time for PR-B.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Infrastructure/observability bug fix, root-caused from production telemetry with a
direct error string. The devex lens moved three things from "nice" to "the deliverable": the
annotation must carry the `-replace` guardrail (the last incident's annotation actively misdirected
the operator), a red gate must notify someone, and the handler→grant lint closes the class rather
than the instance. Named as strategy, not scope: this channel has now failed four times (#4804,
#6178, #6594, #7220) and each fix hardens a single point of failure whose real problem is an
unreplaceable host.

### Product/UX Gate

Not applicable — no file in `## Files to Edit` matches the UI-surface term list or glob superset
(no `components/**`, no `app/**/page.tsx`, no `app/**/layout.tsx`). Mechanical override did not fire;
semantic sweep returns NONE.

## Files to Edit

- `apps/web-platform/infra/infra-config-apply.sh` — **(A)** trap hoist, `errtrace`, pure-assignment
  ERR trap, `on_exit()` with ERR disarm + rc re-pin, `.fatal` handoff, real counters, `.final` move;
  **(B)** seam rename, guard split, orphan-sweep parse hard-fail, `--collect`
- `apps/web-platform/infra/infra-config-gate.sh` — **(A)** fatal message shape + branch suppression
- `apps/web-platform/infra/infra-config-install.sh` — **(B, blocking)** `*.service` content gate
- `apps/web-platform/infra/webhook.service` — **(B)** `StartLimitIntervalSec=0`
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — **(B)** new alias + grant; `--collect`
  argv update to `WEBHOOK_SELF_RESTART`; correct the falsified daemon-reload premise at `:118-123`
- `apps/web-platform/infra/cloud-init.yml` — **(B)** the mirror (both alias sets)
- `apps/web-platform/infra/server.tf` — **(B)** `sudo -n -l` policy probe + `DropInPaths` assertions
- `apps/web-platform/infra/infra-config-apply.test.sh` — extended existing arms + new arms + the
  handler→grant lint
- `apps/web-platform/infra/infra-config-gate.test.sh` — rendered-message arms
- `.github/workflows/apply-deploy-pipeline-fix.yml` — `if: failure()` alert step
- `scripts/followthroughs/infra-config-activation-7220.sh` — **new**, the enrolled soak probe
- `knowledge-base/engineering/architecture/decisions/ADR-159-delivery-is-not-activation.md` — amend
- `knowledge-base/engineering/architecture/diagrams/model.c4` — correct the falsified edge description

## Files to Create

- `scripts/followthroughs/infra-config-activation-7220.sh` (AC21)

## References

- Issue **#7220**; failing run **30811367645**; merge **701e76e6** (#7146, Ref #7103)
- ADR-159 (delivery is not activation), ADR-154 (repair the credential channel, not the host)
- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
- `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md`
- `knowledge-base/project/learnings/2026-07-25-i-added-the-field-that-closes-the-gap-and-nothing-read-it.md`
- `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`
- ERR-trap precedent: `apps/web-platform/infra/inngest-cutover-flip.sh:212-227`
- Soak-probe exemplar: `scripts/followthroughs/ac12-telemetry-positive-control-7103.sh`
