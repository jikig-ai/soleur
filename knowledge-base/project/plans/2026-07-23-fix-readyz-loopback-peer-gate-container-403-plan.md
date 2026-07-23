---
title: Fix /internal/readyz loopback peer-gate 403 to host-side probes (container-networking)
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-23
branch: feat-one-shot-readyz-loopback-peer-gate-container-403
issue: none (standalone bug-fix; unblocks the 2026-07-20 cutover incident #6812 — see "No Closes" note)
---

# 🐛 Fix /internal/readyz loopback peer-gate 403 to host-side probes

## Enhancement Summary

**Deepened on:** 2026-07-23 (headless one-shot; no Task fan-out available — deepening done directly against the code by the planning agent).

**Deepen-plan gates:** 4.6 User-Brand Impact PASS · 4.7 Observability (5-field, no-ssh) PASS · 4.8 PAT-shaped PASS · 4.9 UI-wireframe SKIP (no UI surface) · 4.55 Downtime/Cutover SKIP (no offline-inducing op — probe-transport change only) · 4.5 Network-outage trigger fires *incidentally* on the substrings `503`/`unreachable`/`timeout` (readyz reason vocabulary, NOT a connectivity outage); the fix touches no L3 firewall/DNS/sshd surface, so no deep-dive is warranted.

**Key deepening findings (all verified against code):**
1. **Precedent confirmed** — `docker exec soleur-web-platform <cmd>` is already an established pattern on the PROD container (`ci-deploy.sh:413` `docker exec soleur-web-platform pgrep …`; canary variants at :1714/:2551 use `node`/`bwrap`). The fix adopts the canonical form; it is not novel.
2. **Both callers pass loopback URLs** — `workspaces-cutover.sh:715` (literal `http://127.0.0.1:3000/internal/readyz`) and `luks-monitor.sh:218` (`$READYZ_URL`, defaults to the same). So `docker exec …-into-container` is correct for both; the verify workflow inherits it (runs `luks-monitor.sh` on-host over SSH).
3. **Harness feasibility confirmed** — `mon_run` prepends `$d/bin` to PATH (`workspaces-luks-harness.sh:555`), so the new `$d/bin/docker` PATH stub's `exec "$@"` resolves the sibling `$d/bin/curl` stub. The first harness's `docker()` shell-function stub already exists (line 173) and needs only the `exec <c> curl` delegation branch.
4. **Verify-the-negative** — the plan's negative security claims ("off-host caller still gets 403", "trust boundary unchanged") were re-checked against `readiness.ts:112-114` + `loopback.ts:30-36`: the fix edits **no** gate logic, and there is no `NEXT_PUBLIC_*`/client-exposure surface (server-only endpoint). Claims confirmed, not contradicted.

**New considerations discovered (folded into Sharp Edges / tasks):**
- **Docker permission precondition:** `docker exec` requires the caller to be in the docker group / root. All three paths already run as root — cutover under `sudo`; daily `luks-monitor` under a root systemd timer; the verify workflow's remote commands do root-level `install -m600`/`mkdir /var/lib/…`. No new privilege is introduced, but the fix now hard-depends on host docker access (previously the host curl needed none).
- **`LUKS_MONITOR_READYZ_URL` override seam:** `luks-monitor.sh:46` allows overriding the URL. `docker exec … curl <url>` wraps whatever URL is passed; for the loopback default it is correct. Keep the wrapper unconditional (do NOT branch on URL shape — gold-plating); document that a non-loopback override would probe from inside the container's netns.

## Overview

`GET /internal/readyz` (`apps/web-platform/server/readiness.ts:112-114`, `handleReadyzRequest`)
returns a **persistent 403** to every host-side probe. It gates on **both**
`isLoopbackPeer(req.socket?.remoteAddress)` **and** `isLoopbackHost(req.headers.host)`. The prod
app container (`apps/web-platform/infra/ci-deploy.sh:2639-2659`) runs on the **default docker bridge**
with `-p 0.0.0.0:3000:3000` (NOT `--network host`). A host-side `curl http://127.0.0.1:3000/internal/readyz`
therefore arrives inside the container with the **docker bridge gateway** (e.g. `172.17.0.1`) as
`req.socket.remoteAddress` — never in `isLoopbackPeer`'s allowlist `{127.0.0.1, ::1, ::ffff:127.0.0.1}`
— so readyz answers **403 `{"error":"forbidden"}`**. This is NOT a boot transient (verify run
30005237812 reproduced it 2h after boot at steady state); it is a **topology-permanent** condition of
the bridge-networked container. `app_canary` in the workspaces-luks cutover has therefore **never**
been able to pass in this container topology (`reason=readyz_gate_regression code=403`, cutover run
29995956562), and the daily/verify at-rest certification is blocked for the same reason.

Contrast: `/internal/metrics` (`apps/web-platform/server/index.ts:95-96`) gates on
`isLoopbackHost` **only** — a host-side `curl` sends `Host: 127.0.0.1:3000`, which passes — so metrics
works fine over the same published port. The readyz **peer clause** is original design (the
deep-readiness endpoint added for web-2 LB pooling, #5966 / ADR-068); the peer clause is the
systemic cause behind the still-open 2026-07-20 cutover incident (web-1 `/mnt/data` was plaintext,
dead-man-undone — #6812).

**Fix (lowest blast radius, security boundary fully intact):** run the on-host readyz probes
**inside the container** — `docker exec soleur-web-platform curl -sS http://127.0.0.1:3000/internal/readyz`
— so the socket peer is a **genuine loopback address** (127.0.0.1 in the container's own network
namespace) and the Host header is loopback too. Both gates pass. **Zero lines of the trust boundary
(`readiness.ts`, `loopback.ts` gate logic) change** — an off-host / tunnel caller still receives 403,
by construction. The alternative (widening the peer gate to accept the bridge gateway) is **rejected on
security grounds** — see the [Security Decision](#security-decision-approach-a-vs-approach-b) section.

All three host-side probe call sites route through **one shared helper** — `wl_probe_readyz`
(`apps/web-platform/infra/workspaces-luks-emit.sh:135`): `workspaces-cutover.sh` (app_canary) calls it
directly; `luks-monitor.sh` calls it directly; `.github/workflows/workspaces-luks-verify.yml` SSHes to
the host over the CF-tunnel bridge and runs `luks-monitor.sh`. So the fix is **centralized in
`wl_probe_readyz`** (DP-11 DRY) — the two callers and the workflow inherit it unchanged.

## Premise Validation

- **Root-cause artifacts confirmed present on this branch (not stale):** `readiness.ts:112-114`
  (`!peerLoopback || !isLoopbackHost` → 403); `isLoopbackPeer` allowlist `{127.0.0.1, ::1,
  ::ffff:127.0.0.1}` (`loopback.ts:30-36`); prod `docker run … -p 0.0.0.0:3000:3000` with **no**
  `--network host` (`ci-deploy.sh:2657-2658`); the `readyz_gate_regression` 403 classifier
  (`workspaces-luks-emit.sh:172-173`); the three probe sites (`workspaces-cutover.sh:715`,
  `luks-monitor.sh:46`, `workspaces-luks-verify.yml:311`). All verified by direct read.
- **curl presence in the container image confirmed** (`apps/web-platform/Dockerfile:89`:
  `apt-get install -y --no-install-recommends curl …`). This is the load-bearing precondition for
  `docker exec … curl`; if curl were absent the exec would 000-loop and block cutover forever. Verified.
- **Container name confirmed:** the prod container is `soleur-web-platform` (`ci-deploy.sh:2640`
  `--name soleur-web-platform`); the canary is a distinct `-canary` container not involved on the
  app_canary readyz path (app_canary runs after the PROD container `docker start`).
- **No external blocker issues cited by reference.** The 2026-07-20 incident (#6812) is the thing this
  fix **unblocks**, not a blocker to validate; it stays open (see "No Closes" note).
- **Own capability claims verified, not assumed:** the "three sites collapse to one helper" claim was
  verified by reading each caller; the "metrics works because Host-only" claim was verified against
  `index.ts:95-96` + `loopback.ts:20-24`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task brief) | Reality (verified) | Plan response |
| --- | --- | --- |
| "three host-side probe call sites" edited separately | All three route through the single shared `wl_probe_readyz` helper (cutover + monitor call it; verify runs monitor over SSH) | Fix `wl_probe_readyz` once; no per-caller edit needed beyond a config default |
| readyz returns 403 to host curl (bug) | Confirmed; classifier already maps 403 → `readyz_gate_regression` (emit.sh:172) — the classifier is correct, the transport is wrong | Change transport (docker exec), leave the classifier |
| container runs default bridge, `-p 0.0.0.0:3000:3000` | Confirmed at ci-deploy.sh:2658; also `-p 0.0.0.0:80:3000` (line 2657) | No docker-run change (see Alternatives) |

## User-Brand Impact

**If this lands broken, the user experiences:** the workspaces-luks at-rest cutover stays permanently
blocked → their source code (sole-copy, no durable second copy — model.c4:186) remains **PLAINTEXT at
rest** while the published privacy policy claims LUKS, and the daily/verify **encryption-at-rest
certification cannot pass** (no ground-truth that the live volume is a LUKS mapper serving user data).
A subtly-wrong fix (wrong container name, curl-absent path) fails **closed** — the probe 000-loops and
blocks the cutover, keeping plaintext-at-rest, rather than certifying green falsely.

**If this leaks, the user's workspace confidentiality is exposed via:** `/internal/readyz` returns host
**mount/topology state** (`workspaces_writable`, `workspaces_populated`, cluster-shape) that is
attacker-useful (DoS-tuning, cluster-shape scraping) — the exact reason the endpoint is loopback-gated.
Widening the peer gate wrong (Approach B) would expose this to a direct off-host caller.

**Brand-survival threshold:** single-user incident. (Matches the subsystem's own self-description —
`readiness.ts:23-24` "single-user-incident class". `requires_cpo_signoff: true`; `user-impact-reviewer`
runs at review-time; deepen-plan runs next.)

## Security Decision — Approach A vs Approach B

**Approach A (CHOSEN): run the on-host probes inside the container via `docker exec`.**
- **Trust boundary is unchanged** — `readiness.ts` and `loopback.ts` gate logic are not touched. The
  off-host boundary is preserved *by construction*: an off-host / tunnel caller still presents a
  non-loopback peer AND/OR a non-loopback Host, so it still gets 403. Nothing to re-argue.
- Inside the container's network namespace, `curl 127.0.0.1:3000` connects to the app's own listener;
  `req.socket.remoteAddress` is a **genuine** `127.0.0.1` (or `::ffff:127.0.0.1`) and `Host` is
  `127.0.0.1:3000`. Both clauses pass legitimately — no clause is relaxed.
- Lowest blast radius: one shared-helper transport change + comment corrections + tests.

**Approach B (REJECTED): widen `isLoopbackPeer` to also accept the docker bridge gateway / host-gateway.**
- **The bridge gateway is not a safe proxy for "on-host".** With docker's **default `userland-proxy=true`**,
  the docker-proxy process terminates the inbound connection on the host and opens a *new* connection to
  the container, so **every** connection arriving via the published `0.0.0.0:3000:3000` port — including a
  genuine **off-host** connection — presents to the container as source `172.17.0.1` (the bridge gateway).
  Widening the peer gate to accept `172.17.0.1` would therefore let an off-host attacker who can reach the
  published port directly (exactly the firewall-bypass case the peer clause is defense-in-depth for —
  `readiness.ts:96-97`) pass the peer gate, collapsing the boundary to the **attacker-controlled Host
  header** alone. That **violates the hard constraint** ("a tunnel/off-host caller MUST still get 403").
- Even under `userland-proxy=false` (iptables-DNAT), Approach B is contingent on an **unpinned,
  mutable docker-daemon flag** and on a **subnet-dependent** gateway address (custom networks use
  different subnets; `host-gateway` resolves to the same gateway). A security boundary must not depend on
  an unverified daemon default. Approach A sidesteps the entire question.

**Conclusion:** Approach A has strictly the stronger posture — it keeps both clauses genuinely enforced
and changes nothing an attacker can reach. This rationale is embedded **at the gate** (code comments in
`readiness.ts` / `loopback.ts`) so a future editor does not "simplify" by widening it, and is restated
in the PR body per the task.

## Implementation Phases

### Phase 1 — Centralize the container-scoped transport in `wl_probe_readyz`
- `apps/web-platform/infra/workspaces-luks-emit.sh`:
  - Add a container-name knob near the top of the file (mirroring the existing default-var idiom):
    `: "${WL_READYZ_CONTAINER:=soleur-web-platform}"` (overridable for tests; defaults to the prod
    container name verified at ci-deploy.sh:2640).
  - In `wl_probe_readyz` (line 151), change the transport from
    `resp="$(curl -sS -w "\\n%{http_code}" --max-time 5 "$url" 2>/dev/null || printf '\n000')"`
    to
    `resp="$(docker exec "$WL_READYZ_CONTAINER" curl -sS -w "\\n%{http_code}" --max-time 5 "$url" 2>/dev/null || printf '\n000')"`.
  - **Fail-closed preserved:** if the container is down / `docker exec` fails, the `|| printf '\n000'`
    path yields code `000` → `readyz_unreachable` → rc 1 (retries then deadlines). No false green.
    Update the function's header comment to note the docker-exec transport + why (bridge topology).
- Update the stale reachability comment in `apps/web-platform/infra/luks-monitor.sh:43-45` — it currently
  claims readyz is "reachable from the host" over the published port; the measured reality is that a
  host-published-port curl gets 403 (bridge-gateway peer), so on-host consumers reach it **only via
  `docker exec` into `soleur-web-platform`**. State the measured fact (per the "removing a false claim
  can strengthen a false claim" caution — 2026-07-22 learning): host curl → 403, docker-exec → genuine
  loopback.

### Phase 2 — Correct the gate rationale comments (no logic change)
- `apps/web-platform/server/readiness.ts:92-100`: clarify that "on-host consumers MUST run on loopback"
  means, on the default-bridge topology, **from inside the container** (docker exec), because a
  host-published-port peer is the bridge gateway, not loopback. Add the one-line "do NOT widen the peer
  gate to the bridge gateway — under docker userland-proxy the gateway is indistinguishable from
  off-host" note so the next editor sees the rejected alternative at the gate.
- `apps/web-platform/server/loopback.ts:8-19`: refine the `isLoopbackHost` doc so it no longer implies
  readyz is reachable by a bare host curl. Distinguish: **metrics** (Host-only gate) IS reachable via the
  host-published port; **readyz** (peer + Host) is reachable only from inside the container. (Logic in
  both functions is unchanged.)

### Phase 3 — Tests (RED before GREEN)
- **`apps/web-platform/test/server/readiness.test.ts` (vitest) — the security-lock unit test:** add
  cases that pin the container-networking peer behaviour:
  - `remoteAddress "172.17.0.1"` (docker bridge gateway) + Host `"127.0.0.1:3000"` → **403** (asserts
    the bridge gateway is NOT loopback — a regression that widened the gate to the gateway fails here).
  - `remoteAddress "::ffff:172.17.0.1"` (mapped form) + Host `"127.0.0.1:3000"` → **403**.
  - (existing 127.0.0.1 / ::1 / ::ffff:127.0.0.1 → 200/503 cases stay — they model the in-container
    peer that `docker exec` produces.)
- **`apps/web-platform/infra/workspaces-luks-harness.sh` — adjust BOTH stub blocks** so the existing
  readyz cases pass through the new `docker exec … curl` transport:
  1. First harness (shell-function stubs, `run_case`, used by `workspaces-luks-freeze.test.sh`): change
     the `docker()` stub (line 173) to delegate the `docker exec <container> curl …` shape to the
     `curl()` stub: when `$1 = exec` AND `$3 = curl`, `shift 2` then `"$@"` (invokes the `curl()`
     function), else record + `return 0` unchanged. **HARNESS RULE (2026-07-22 learning):** this stub
     lives inside a single-quoted `bash -c '…'` body — **no apostrophes** in the added lines.
  2. Second harness (PATH-stub scripts, `mon_prepare`, used by `luks-monitor.test.sh`): add a new
     `$d/bin/docker` executable stub that records to `$CALLS` and, for `exec <container> curl …`,
     `shift 2` then `exec "$@"` (resolves the `$d/bin/curl` PATH stub, since `mon_run` puts `$d/bin`
     first on PATH — harness line 555).
- **Behavioural transport assertion (the KEY test — prevents silent revert to bare host curl):** in a
  freeze-test case AND a monitor-test case, assert `$CALLS` contains
  `docker exec soleur-web-platform curl` on the readyz probe (anchor on the full transport, per
  `cq-assert-anchor-not-bare-token`). Without this, a revert of `wl_probe_readyz` to a bare host `curl`
  (which 403s in prod) would still pass the body-based cases because the harness stubs curl regardless.

## Files to Edit
- `apps/web-platform/infra/workspaces-luks-emit.sh` — `wl_probe_readyz` transport → `docker exec`; add `WL_READYZ_CONTAINER` default; header comment.
- `apps/web-platform/infra/luks-monitor.sh` — correct the stale "reachable from the host" comment (lines 43-45). No logic change.
- `apps/web-platform/server/readiness.ts` — clarify the on-host-consumer comment + embed the "do not widen the peer gate" rationale. **No gate-logic change.**
- `apps/web-platform/server/loopback.ts` — refine the metrics-vs-readyz reachability comment. **No logic change.**
- `apps/web-platform/test/server/readiness.test.ts` — add bridge-gateway-peer → 403 cases.
- `apps/web-platform/infra/workspaces-luks-harness.sh` — `docker exec … curl` delegation in both stub blocks.
- `apps/web-platform/infra/workspaces-luks-freeze.test.sh` — add the `docker exec … curl` transport assertion on the app_canary readyz path.
- `apps/web-platform/infra/luks-monitor.test.sh` — add the `docker exec … curl` transport assertion on the monitor readyz path.

## Files to Create
- None. (No new script, module, workflow, or infra resource.)

## Architecture Decision (ADR/C4)

**No new ADR file, no C4 edit — with the enumeration that justifies "none":**
- **Trust boundary unchanged.** The fix moves the client transport (on-host probe → into the container),
  not the resolver/dispatch/trust boundary. `readiness.ts` / `loopback.ts` gate logic is untouched, so
  this neither creates nor diverges from an ADR (ADR-068 established the deep-readiness endpoint; this
  implements its documented on-host access path, it does not reverse it).
- **C4 completeness check (all three `.c4` files read).** `readyz` / `readiness` / `luks-monitor` /
  `workspaces-cutover` / `resource-monitor` are **not modeled** as C4 elements (grep of `model.c4`,
  `views.c4`, `spec.c4` — zero hits). Enumerated for this change: (a) external human actors — none new;
  (b) external systems/vendors — none new (no Cloudflare/Doppler/R2/Sentry edge changes); (c)
  containers/data-stores — the app container (`webapp`) and `workspacesVolume` are already modeled and
  the `hetzner -> workspacesVolume` bind-mount edge is unchanged; (d) access relationships — host ops
  script → app container internal readyz, an internal host↔container transport that is not a modeled
  edge and whose trust boundary does not move. → **no C4 impact.**
- The durable design rationale (why not widen the gate) lives **at the gate** in `readiness.ts` /
  `loopback.ts` comments + the PR body. If deepen-plan / plan-review judges the security rationale
  ADR-worthy, elevate to a short ADR then; the plan does not defer a *required* ADR.

## Observability

```yaml
liveness_signal:
  what: readyz probe reason code (readyz_gate_regression | readyz_not_ready | readyz_unreachable | success) emitted by app_canary (cutover), the daily luks-monitor, and the verify workflow
  cadence: per-cutover (app_canary) + daily (luks-monitor.timer) + on-dispatch (workspaces-luks-verify.yml)
  alert_target: Sentry feature=workspaces-luks op=workspaces-luks-drift (emit_drift) + Better Stack journald
  configured_in: apps/web-platform/infra/workspaces-luks-emit.sh (wl_probe_readyz + workspaces_luks_emit)
error_reporting:
  destination: Sentry (emit_drift → workspaces_luks_emit); GITHUB_STEP_SUMMARY + ::error:: on the verify workflow
  fail_loud: true (readyz failure aborts app_canary via die; verify workflow exits nonzero with a reason-classified ::error::)
failure_modes:
  - mode: transport reverted to bare host curl (regression) → prod readyz answers 403
    detection: in-surface — the readyz JSON body (workspaces_writable/workspaces_populated) is unreadable and the classifier lands 403 → readyz_gate_regression; the freeze/monitor test transport assertion fails in CI first
    alert_route: CI test failure (pre-merge) + Sentry readyz_gate_regression (post-deploy)
  - mode: container down / curl absent in image → docker exec fails
    detection: in-surface — code 000 → readyz_unreachable (fail-closed, retries then deadlines); never a false green
    alert_route: Sentry readyz_unreachable + app_canary die
  - mode: volume unmounted/empty but serving → readyz ready:false
    detection: in-surface — workspaces_writable/workspaces_populated fields in the readyz body (503, readyz_not_ready)
    alert_route: Sentry readyz_not_ready + verdict triage table (runbook §5)
logs:
  where: journald (container + luks-monitor logger -t) → Better Stack Logs source 2457081; GitHub Actions run logs for verify
  retention: Better Stack Logs retention (standard); GH Actions run retention
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts && bash apps/web-platform/infra/workspaces-luks-freeze.test.sh
  expected_output: readiness.test.ts bridge-gateway-peer cases assert 403; freeze test asserts "docker exec soleur-web-platform curl" on the app_canary readyz path — no ssh
```

## Infrastructure (IaC)

Skip — introduces no new infrastructure (no server, systemd unit, secret, vendor account, DNS, cert,
firewall rule, or persistent runtime process). Pure code change to existing on-host ops scripts + the
app's TS comments/tests. The docker container topology (`-p 0.0.0.0:3000:3000`, default bridge) is
**unchanged** by design (see Alternatives).

## Open Code-Review Overlap

None. Scanned all 60 open `code-review` issues (`gh issue list --label code-review --state open`); none
reference `readiness.ts`, `loopback.ts`, `workspaces-luks-emit.sh`, `workspaces-cutover.sh`,
`luks-monitor.sh`, `workspaces-luks-harness.sh`, `workspaces-luks-verify.yml`, `readiness.test.ts`, nor
the tokens `readyz` / `loopback` / `workspaces-luks` / `app_canary` / `peer gate`.

## Domain Review

**Domains relevant:** Engineering/Security (infra + trust-boundary reasoning).

This is an infrastructure/security bug-fix with no user-facing UI surface (no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit) — **Product/UX Gate: NONE**. The
security lens is the load-bearing one and is handled by the Security Decision section + the
single-user-incident threshold (which routes `user-impact-reviewer` at review and CPO sign-off at plan
time). No GDPR/regulated-data surface (no schema, migration, auth flow, API route, or `.sql`) — GDPR
gate skipped.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `wl_probe_readyz` (`workspaces-luks-emit.sh`) invokes readyz via
      `docker exec "$WL_READYZ_CONTAINER" curl …`; `WL_READYZ_CONTAINER` defaults to `soleur-web-platform`.
      Verify: `grep -n 'docker exec "\$WL_READYZ_CONTAINER" curl' apps/web-platform/infra/workspaces-luks-emit.sh` returns 1 line.
- [ ] AC2: `readiness.test.ts` asserts `remoteAddress="172.17.0.1"` + `Host="127.0.0.1:3000"` → **403**
      AND `"::ffff:172.17.0.1"` → 403. Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts` → all pass.
- [ ] AC3: the freeze test AND the monitor test each assert `$CALLS` contains
      `docker exec soleur-web-platform curl` on the readyz probe. Run:
      `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh` and
      `bash apps/web-platform/infra/luks-monitor.test.sh` → all pass.
- [ ] AC4: existing readyz body/status behaviour is preserved — freeze T22/T22b/T22c and the monitor
      readyz cases still pass (ready:false → die/fail; unreachable → fail-closed).
- [ ] AC5: **trust boundary unchanged** — `git diff` shows NO change to the gate logic in
      `readiness.ts` (`!peerLoopback || !isLoopbackHost`) or the `isLoopbackPeer`/`isLoopbackHost`
      function bodies in `loopback.ts` (comment-only edits there).
- [ ] AC6: typecheck clean — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] AC7: full infra shell suite green — `bash apps/web-platform/infra/test-all.sh` (or the repo's
      shell-test entrypoint) passes, including the harness stub changes across both blocks.
- [ ] AC8: PR body justifies Approach A over Approach B (the userland-proxy argument) and notes that
      web-1 `/mnt/data` is currently a live LUKS mapper being certified — this fix unblocks that
      certification. **No `Closes #6812`** (see note).

### Post-merge (operator / pipeline)
- [ ] AC9: after deploy, dispatch `workspaces-luks-verify.yml` (read-only) and read the **emitted marker**
      (per 2026-07-22 learning — read the reason, not the run status): the readyz arm no longer reports
      `readyz_gate_regression`; a ready host reports success. **Automation:** `gh workflow run
      workspaces-luks-verify.yml` via the `gh` CLI (no ssh, no operator dashboard).

## Test Scenarios

| Scenario | Peer (remoteAddress) | Host header | Expected |
| --- | --- | --- | --- |
| In-container probe (docker exec) — the fix's path | 127.0.0.1 / ::ffff:127.0.0.1 | 127.0.0.1:3000 | 200/503 (readiness body) |
| Host-published-port curl (the bug) | 172.17.0.1 (bridge gateway) | 127.0.0.1:3000 | **403** — why docker exec is required |
| Off-host direct TCP (boundary must hold) | off-host IP or 172.17.0.1 under userland-proxy | attacker-set | **403** (peer and/or Host fails) |
| Tunnel / public traffic | bridge gateway (cloudflared→origin) | public hostname | **403** (isLoopbackHost false) |
| Container down / curl-absent | n/a (docker exec fails) | n/a | code 000 → readyz_unreachable → fail-closed |

## Sharp Edges

- **Harness `bash -c` single-quote rule (2026-07-22 learning, Session Error #1):** the first-harness
  `docker()` stub lives inside a single-quoted `bash -c '…'` body — the added delegation lines must
  contain **no apostrophes**, or 3 suites fail at parse time.
- **curl MUST exist in the image** — verified at Dockerfile:89. If a future image change drops curl, the
  probe 000-loops (fail-closed, but blocks cutover forever). If that ever happens, switch the in-container
  probe to `node -e` (node is always present) rather than reverting to a host curl.
- **`docker exec` requires host docker access (root/docker-group).** All three probe paths already run as
  root (cutover under `sudo`; daily `luks-monitor` under a root systemd timer; the verify workflow's remote
  commands do root-level `install`/`mkdir`), so no new privilege is added — but the probe now hard-depends
  on host docker access where the old host curl needed none. A caller that lost docker access would see
  `docker exec` fail → 000 → `readyz_unreachable` (fail-closed).
- **Keep the `docker exec … curl` wrapper unconditional** — do NOT branch on whether `$url` is loopback
  (`LUKS_MONITOR_READYZ_URL` can override it). Branching is gold-plating; the default URL is loopback and a
  non-loopback override simply probes from inside the container's netns.
- **Do NOT tighten the published port to `127.0.0.1:3000:3000` or add `--network host` as a "simpler
  fix"** — the port is also consumed by `resource-monitor.sh` (host curl of `/internal/metrics`) and by
  cloudflared→origin; both changes have wider blast radius than the probe transport (see Alternatives).
- **Do NOT widen `isLoopbackPeer`** — under docker's default userland-proxy the bridge gateway is
  indistinguishable from off-host traffic; the rationale is embedded at the gate to stop a future regress.
- **A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6** —
  this one is filled with concrete artifact + vector + threshold.
- **Concurrent-worktree hygiene (2026-07-22 Session Error #3):** commit each verified unit immediately;
  if a shared-worktree agent's `git checkout -- <file>` wipes uncommitted edits, three brand-new tests
  going RED against work you believe done = a silent revert — `git diff HEAD <file>` before re-debugging.

## Alternatives Considered

| Alternative | Why not |
| --- | --- |
| Widen `isLoopbackPeer` to accept `172.17.0.1` / host-gateway | Rejected on security grounds — collapses the off-host boundary under docker userland-proxy (see Security Decision). Violates the hard constraint. |
| Bind the port to `-p 127.0.0.1:3000:3000` | Doesn't fix the peer address (host→container still traverses the bridge → gateway peer → 403); and would break off-host reachability the app/cloudflared may rely on. |
| `--network host` for the prod container | Would make host curl a genuine loopback peer, but is a large topology change (drops network isolation, changes the metrics/port model, affects bwrap/seccomp assumptions) far beyond a probe-transport bug fix. Out of scope. |
| Drop the peer clause, keep only Host | Explicitly forbidden by the task (must preserve the off-host boundary); Host alone is attacker-controllable on a direct off-host TCP connection. |

## Note — No `Closes #` for the 2026-07-20 cutover incident

This is a **standalone bug-fix PR** that UNBLOCKS the still-open workspaces-luks cutover incident
(#6812). Do **NOT** add any `Closes #6812` (or `Closes` for the incident) — #6812 stays open until the
cutover is separately re-run and certified. Reference it with `Ref #6812` only. web-1 `/mnt/data` is
**currently a live LUKS mapper** (encryption at rest in effect); this fix unblocks its daily/verify
at-rest certification.
