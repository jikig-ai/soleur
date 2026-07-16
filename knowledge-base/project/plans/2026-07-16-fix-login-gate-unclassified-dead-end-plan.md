# fix: drain the `unclassified` dead-end in the zot/GHCR docker-login gate (#6497)

---
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 6497
date: 2026-07-16
---

## Enhancement Summary

**Deepened:** 2026-07-16 · **Panel:** security-sentinel, spec-flow-analyzer,
observability-coverage-reviewer, user-impact-reviewer, verify-the-negative sweep, test-harness
research. **Every finding below was verified by execution before being applied.**

### The plan as first drafted would have shipped a green PR that failed its own contract

Four agents converged **independently** on the same two defects:

1. **The `unclassified`-only hatch + the `cred_store` arm cancel each other.** Both surviving
   cred-store hypotheses share the measured prefix `error saving credentials`, so both would
   classify as `cred_store`, the hatch would never fire, and they would be **byte-identical in the
   emit**. `cred_store` becomes `unclassified` under a new name — *in the PR that exists to drain
   it*. → hatch now fires on **every failed login** (UC-3).
2. **`stderr_chars` alone cannot decide H-B** — H-B is a disjunction (stdout **or** nowhere), so
   `stderr_chars=0` *restates* it. This is the plan's own Research-Reconciliation §5 defect
   recurring one level down. → capture **stdout** + emit **`rc`** (which the plan measured, then
   dropped).

### Also caught, all by execution

| finding | evidence |
|---|---|
| **The dominant abort class is a nonzero rc, not an unset var.** `grep -q`'s normal non-match kills the script under `set -e`; `${x:-}` cannot touch it. AC2 had a hole the size of the diff's likeliest failure. | measured 3-construct containment table → **subshell** is the only mechanism |
| **A bare `mktemp` aborts when `/tmp` is full — which is hypothesis H-C.** The instrument would wedge prod in the exact scenario it diagnoses. | → variable capture; also designs out the `tail -c 400` edge and AC5 |
| **`tok` as specified admitted a Form-A filter** — same output set, but degrades to *disclosure* instead of a wrong label. 3 of 8 allow-list entries were provably dead, creating the pressure to loosen that leaks. | → Form B mandated; AC3 made **structural** (`grep printf.*$` → zero) |
| **`kw` contained only the three falsified tokens** — empty for every surviving hypothesis. | → enumerated from the measured table |
| **`refetch_ghcr_and_relogin`'s stdout is a typed control channel** logged raw at `:829`. A reflexive `2>&1` pipes unclassified stderr into journald — **below AC3's Sentry-scoped sightline** — and silently discards the #6400 recovery. | `:747/:749` → `:825`/`:925` |
| **Both prescribed Better Stack commands were malformed.** `--since 60` fails the `^([0-9]+)([hmd])$` regex → `WHERE dt >= '60'`. **The plan's only no-SSH probe did not run.** And `--grep ZOT_GATE` cannot see the GHCR `PRELUDE:` half. | re-ran the script's own parser |
| **AC13 was RED on correct code** (success path emits no `class=`) *and* vacuous on the `cred_store` branch. R5's "green under every hypothesis" was false. | → three-way restatement |
| **Two more confidently-wrong arms**: daemon-socket EACCES → `transport` (no `credentials` literal, so `cred_store` can't rescue it); `504` → `transport` (bare `timeout` outranks 5xx). | measured against the real classifier |
| **The rename falsifies `:636-647`** — its zot-measured *"NEVER 403 → unreachable → tripwire"* claim is false for GHCR, which **does** 403. | Phase 5 |
| **The existing leak-canaries drive a 401** → they never execute the hatch and would stay green while it leaks. | `:3583`/`:3600` |
| Field-name drift `stderr_len`/`stderr_chars` across 30 sites | normalized |

**Net:** 14 findings applied. The two most consequential — the cancelled hatch and the missing
stdout capture — would each, alone, have cost the second telemetry PR this plan exists to prevent.
That is learning §9 holding exactly: *every catch was an execution, not a reading.*

---

## Overview

`ci-deploy.sh`'s docker-login gate cannot name its own failure. Every deploy since 08:27Z
emits `ZOT_GATE: docker login … FAILED class=unclassified http=none`, and the two GHCR login
sites 90 lines above it discard stderr entirely (`>/dev/null 2>&1`). The one datum that would
decide the cause is destroyed at the source in two places and falls into an undifferentiated
bucket in the third.

This PR **buys the datum**. It does not attempt the repair — we do not yet know the cause, and
a guess ships to every web host.

Scope: **one script + its test suite**, plus two falsified comments in `zot-registry.tf` and
the re-scoping of #6497 itself.

**This plan's central discipline** comes from
[`2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md`][l]
§9, written about this exact issue five PRs ago:

> **the prose control does not work.** What actually caught all five here was **mechanical**: a
> `docker run` against the pinned image, a mutation battery that *relocated* attributes rather
> than deleting them, a real `terraform plan` through the real gate. Every catch was an
> execution, not a reading.

So every claim below that could have been derived was instead **measured**, at plan time. That
measurement overturned **four** premises in the task brief and **one shipped causal claim**.
See Research Reconciliation. This is the fifth consecutive session in this class; the plan is
structured so that the sixth is caught by a command, not by a paragraph.

[l]: ../learnings/2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md

---

## Research Reconciliation — Brief vs. Measured Reality

All measurements run 2026-07-16 against `docker` CLI 29.4.3, and **independently re-measured on
29.4.3 at /work Phase 0 — every surviving row reproduced byte-for-byte.** (~~re-measure on the
pinned host version at /work Phase 0~~ — **there is no pinned host version**: `cloud-init.yml:428`
installs `docker-ce` unpinned. See Research Reconciliation 9 and the amended AC1; the instrument
now emits `docker_ver` so the host self-reports.) Method: a live `registry:2` on
`localhost:15999` (answers `/v2/` 200) so the login reaches the credential-store write, which
only happens **after** auth succeeds. Measured strings were then fed through the **real**
`_zot_login_failure_class` extracted from `ci-deploy.sh:661-676`.

| # | Brief's claim | Measured reality | Plan response |
|---|---|---|---|
| 1 | §C: add arm matching `not a TTY` | **FALSIFIED.** Real string is `error: cannot perform an interactive login from a non-TTY device` — lowercase, hyphenated. `not a TTY` **never matches**. | Token dropped. Only measured literals become arms. |
| 2 | §C: add arm matching `credential helper` | **FALSIFIED.** The phrase never appears. Helper failures render `error storing credentials - err: exec: "docker-credential-<name>": executable file not found in $PATH`. | Token dropped. |
| 3 | §C: add arm matching `Cannot connect to the Docker daemon` | **NOT REPRODUCED** on the login path. A dead `DOCKER_HOST` socket rendered `time="…" level=info msg="Error logging in to endpoint, trying next endpoint"`. | Token dropped — unmeasured. Escape hatch covers it instead. |
| 4 | §3: leading hypothesis = credential-store WRITE fails (`/home/deploy/.docker/config.json`, UID 1000) | **PARTIALLY FALSIFIED BY LIVE DATA.** The *permission* variant renders `error saving credentials: open <path>: permission denied` → contains `permission denied` → the **existing `transport` arm already matches it**. We observe `unclassified`, so the EACCES variant is **ruled out**. Only the *helper* variant survives — or a mode nobody has listed. | Hypothesis narrowed (see Hypotheses). The plan does **not** build for a specific cause. |
| 5 | §3: `class=unclassified http=none` implies stderr text that matched no arm | **INCOMPLETE.** An **empty** stderr *also* renders exactly `class=unclassified http=none` (`_zot_login_failure_class "" → unclassified`). The gate cannot distinguish "text matched nothing" from "no text at all" — different bugs, different fixes. | **This is the highest-value field in the escape hatch.** `stderr_chars` is decisive, not decorative. |
| 6 | §"ISSUE HYGIENE": open a successor issue for "zot serves zero pulls, not achieved end-to-end" | **DUPLICATE.** #6497's own body already states *"zot has served **zero pulls in 90 days**"* and owns the 3-condition decomposition. #6122 (umbrella) is OPEN and owns end-to-end. | **User-Challenge** — recorded in `decision-challenges.md`. Operator intent satisfied via a correcting comment on #6416 instead. |
| 7 | §"CONSTRAINTS": "ci-deploy.sh is NOT an `OPERATOR_APPLIED_EXCLUSION` — ships on merge" | **TRUE, and now verified by the right question** (learning §6). Not because it is a `.sh`: because `apply-deploy-pipeline-fix.yml` is `on: push: branches:[main]` with `paths:` including `apps/web-platform/infra/ci-deploy.sh` (`:66`), and its `apply` job (`:183`) is gated only by a commit-message kill-switch — **not** `workflow_dispatch`. | Recorded with the enclosing-job + trigger evidence, per learning §6. |
| 8 | §1: "#6497's ORIGINAL cause is FIXED AND CONVERGED" | **IMPRECISE — it was FALSIFIED, not fixed.** See below. | Drives the re-title and the PR body. |
| **9** | **This plan's own AC1/Phase 0.1: "re-run the measurement battery on the pinned host docker version"** | **FALSIFIED AT /work PHASE 0. There is no pinned version.** `cloud-init.yml:424-428` adds Docker's official apt repo and runs `apt-get install -y docker-ce` **UNPINNED** — the host gets whatever was latest at boot. `soleur-web-platform` (web-1) was created **2026-03-17T06:37:09Z** (live Hetzner API) and has not been replaced since, so its docker is whatever `docker-ce` was current in March 2026. Today's candidate for noble is `5:29.6.1-1~ubuntu.24.04~noble` (measured in a real `ubuntu:24.04` container). The `docker/29.6.1` User-Agent in zot's session logs is almost certainly the **CI runner** (fresh, latest), **not** web-1 — do not attribute it to web-1. **web-1's actual docker version is not observable in any current telemetry.** | **AC1 amended (see AC1).** Per `hr-no-dashboard-eyeball-pull-data-yourself`, the missing signal becomes a **monitored marker**: the hatch emits a `docker_ver` field so the next occurrence self-reports. The follow-up issue (Phase 6.3) records the first observed host value; any arm whose literal does not appear in the host's measured output is amended then. |
| **10** | **Phase 4 finding 2 / task 2.2: promote a `cli_daemon` arm on `docker.sock` \| `unix://` \| `_ping`** | **UNREPRODUCIBLE ON THE LOGIN PATH — measured on 29.4.3.** `docker login` **never contacts the daemon socket**: with a completely dead `DOCKER_HOST=unix:///nonexistent/d.sock`, `docker login` renders **no daemon error at all** (it renders the registry error, `time="…" level=info msg="Error logging in to endpoint, trying next endpoint"`), while `docker ps` on the same dead socket renders `failed to connect to the docker API at unix:///nonexistent/d.sock: … connect: no such file or directory`. Login is CLI-side in 29.x. The plan's proposed literal (`Got permission denied while trying to connect to the Docker daemon socket…`) is **not** what 29.4.3 renders, and is not on this path regardless. | **NO `cli_daemon` ARM SHIPS** — the plan's own rule: *"If AC1 cannot reproduce them, they stay `kw` probes and no arm ships (learning §2)."* The three discriminators are demoted to `kw` probes, where being wrong is free. This also retires the `cli_daemon` row from UC-3's confidently-wrong table. |
| **11** | **Phase 3 / task 2.8: add a mandatory `registry: zot\|ghcr` tag to the Sentry beacon** | **KEY COLLISION.** `zot_gate_degraded_event` (`:715`) already emits `registry: "zot-gate-degraded"` in the **same** `tags` object. A second `registry` key is silently last-wins in `jq` — it would **destroy** the existing event-type tag. | Discriminator renamed **`login_registry`** (`zot`\|`ghcr`). The pre-existing `registry: "zot-gate-degraded"` tag is left untouched. |
| **12** | **Phase 3 P0 / task 2.9: "the class is returned via a named global mirroring `RECOVERY_STAGE`"** | **UNIMPLEMENTABLE FOR THIS FUNCTION — measured.** `RECOVERY_STAGE` works because `_ghcr_pull_or_recover` is called **directly**. `refetch_ghcr_and_relogin` is called via **command substitution at BOTH sites** (`:825`, `:925`) — `stage="$(refetch_ghcr_and_relogin)"` — which is a **subshell**, so a global set inside it is discarded (measured: `G` stays `before`). The function's own comment already records that it "runs in a `$(…)` subshell". | The helper **emits its own journald line** for the class + hatch. This satisfies the constraint set more simply than a global could: stdout stays the typed control channel untouched, and GHCR is **journald-only by decision** anyway (Phase 3 Sentry-volume note), so no value needs to cross the subshell boundary at all. |

### 8 in full — the htpasswd cause was falsified by the experiment it motivated

#6497's body names a root cause (boot-baked htpasswd diverges from Doppler) derived from a
**discriminator argument**: *"crane/cosign **push** authenticates against the same
`/etc/zot/htpasswd` in the same window that `zot-pull` is rejected. One entry current, one
stale — the shape only a per-entry divergence produces."*

The `registry-host-replace` dispatch (run 29482827061, 08:15Z) re-baked htpasswd from current
Doppler. That **is** the experiment: re-bake → login should recover. Result:
`htpasswd_pull_matches=true htpasswd_push_matches=true`, and `login_failed` **continues on
every deploy since 08:27Z**. The hypothesis is refuted.

The discriminator claimed a uniqueness it did not have. "Push works, pull login fails" is
*also* produced by a **local** docker-login failure affecting both registries — which the
discriminator never enumerated. That is the same defect class as learning §2 (deriving a
vendored service's behaviour instead of measuring it), now in its own root-cause analysis.

**The htpasswd Terraform edge remains correct and worth keeping** — a boot-baked value genuinely
needs a convergence edge, and rotation genuinely did not converge. It simply was **not** the
cause of WEB-PLATFORM-5B. Two shipped comments now assert that it was:

- `zot-registry.tf:108-109` — *"every pull login is rejected forever … which is exactly what
  #6497 / Sentry WEB-PLATFORM-5B was."*
- `zot-registry.tf:332` — *"the WEB-PLATFORM-5B defect."*

Both are **false comments about the cause of the defect, in the file whose false comment started
this thread**. Correcting them is in scope (Phase 4): leaving them is how the next engineer
concludes WEB-PLATFORM-5B is solved.

---

## Hypotheses

**Network-outage gate (plan Phase 1.4) — fired** on `unreachable`/`timeout` in the description.
The checklist mandates L3→L7 order: firewall + DNS/routing **before** any service-layer
hypothesis. Both are **verified green, mechanically, and not by inspection**:

- **L3/L4 — verified.** `ci-deploy.sh:869` runs a `curl /v2/` probe **before** the login and
  emits `reason=probe_unreachable` on failure. We observe `reason=login_failed`, never
  `probe_unreachable` ⇒ web-1 reached `10.0.1.30:5000` over HTTP seconds before the login to
  that same endpoint failed. The firewall/route/DNS path is **proven open by the script's own
  prior statement**, not assumed.
- **L3 — corroborated.** Live Hetzner API: `soleur-inngest` is a healthy private-net member at
  `10.0.1.40`. The `soleur-inngest-prd` string in the degraded rows is the Better Stack **source
  label** (source `soleur-inngest-vector-prd`, id 2457081), not the emitting host. Every event is
  `host=soleur-web-platform` (web-1, 10.0.1.10), `_SYSTEMD_UNIT=webhook.service`. **The host
  attribution in #6497 is wrong** — do not chase the inngest host.
- **L7 — where the defect is.** The measured classifier table below.

`transport` is *not* silently absorbing this: the `transport` arm already matches
`connection refused|no route to host|network is unreachable|connection reset|broken pipe|: EOF|
no such host|temporary failure in name resolution|context deadline exceeded|i/o timeout|timed
out|timeout|permission denied`. Observing `unclassified` means the stderr matched **none** of
those. The network hypothesis is excluded by the instrument itself.

### Measured classifier discrimination table

Real `_zot_login_failure_class` fed the **measured** strings:

| Failure mode | rc | stderr (measured) | Current class |
|---|---|---|---|
| unroutable host | 1 | `…dial tcp …: connect: no route to host` | `transport` ✓ |
| real 401 | 1 | `…failed with status: 401 Unauthorized` | `authn_rejected` ✓ http=401 |
| **credsStore helper missing** | 1 | `error saving credentials: error storing credentials - err: exec: "docker-credential-X": executable file not found in $PATH, out: ``` | **`unclassified`** ← matches observed |
| **config-dir EACCES** | 1 | `error saving credentials: open <path>.json<rand>: permission denied` | **`transport`** ← **MISCLASSIFIED** |
| **empty stderr** | — | *(none)* | **`unclassified`** ← matches observed |
| **disk full (cred write)** | 1 | `error saving credentials: write <path>: no space left on device` | **`unclassified`** |
| **non-TTY** | 1 | `error: cannot perform an interactive login from a non-TTY device` | **`unclassified`** |
| corrupt config.json | **0** | warning only — **login SUCCEEDS** | n/a — **hypothesis eliminated** |

Two findings fall straight out and neither was in the brief:

1. **`unclassified` currently holds ≥4 distinct modes.** Observing it discriminates almost
   nothing. The escape hatch's job is precisely to split this bucket — that is the deliverable.
2. **`config-dir EACCES` is misclassified as `transport` today.** A credential-store permission
   error routes the operator to the network subsystem. This is the **exact mirror-image** of the
   defect the 2026-07-15 review caught (a bare `denied` arm stealing `connect: permission denied`
   *from* transport); now `transport`'s bare `permission denied` steals a cred-store error. It is
   also **live evidence**: because we see `unclassified` and not `transport`, the EACCES variant
   is ruled out.

**Surviving hypotheses** (deliberately not narrowed further — the PR exists to decide, not guess):
H-A credsStore helper broken/missing · H-B empty stderr (output went to stdout, which is
`>/dev/null`, or nowhere) · H-C disk-full on the cred write · H-D a mode not yet enumerated.

---

## User-Brand Impact

**If this leaks, the user's credentials are exposed via:** the Sentry beacon and the journald →
Better Stack path. `docker login` stderr can echo a **username**, and some registries echo the
attempted credential. `ZOT_PULL_USER` / `GHCR_READ_USER` are **the founder's own credentials**,
and the founder is Soleur's single non-technical target user — a credential of theirs landing in
a third-party sink **is** the single-user exposure, no transitivity needed. The transitive leg
matters too: **a leaked GHCR read credential is a supply-chain path to every end user of the web
platform** (pull the private image, read what is baked into it). An escape hatch implemented as a
passthrough — or a reflexive `2>&1` inside `refetch_ghcr_and_relogin`, which pipes raw stderr
into journald **below AC3's Sentry-scoped sightline** (Phase 3 P0) — ships exactly that.

**If this lands broken, the user experiences:** a wedged deploy pipeline. `ci-deploy.sh` runs
under `set -euo pipefail`; **a nonzero rc from a `grep -q` probe's normal non-match — or an
unbound variable — aborts the whole script**, and prod freezes on the running tag with no new
release able to land (the #6400 shape: prod pinned ~10h). The 2026-07-15 review's **#1 P1 was
this class** — a probe whose bare expansion took the entire telemetry line dark, with the guards
written for that case sitting 8 lines below the line that already killed the script.

**Brand-survival threshold:** `single-user incident`.

> **The threshold rests on the leak, not the wedge — state it in that order.** Re-derived, not
> inherited: the invoking criterion is *one user's data, workflow, or money exposed, lost, or
> charged incorrectly*. A wedged pipeline exposes no data, loses no data, charges nothing — the
> container keeps serving and no live session breaks. **On the letter, the wedge alone argues the
> threshold DOWN toward `none`**, and a reader could reasonably downgrade this plan on it. The
> **credential vector sustains the threshold on its own.** What the wedge adds is second-order and
> worth naming precisely: prod pinned for ~10h means **a user-data incident occurring inside that
> window cannot be mitigated by shipping.** That is a real harm; it is not the primary one.

Consequences, both binding: `requires_cpo_signoff: true`, and `user-impact-reviewer` runs at
review time. Per learning §9, the multi-agent panel is the control that actually works here — and
it earned that on this plan: four agents independently converged on the `unclassified`-only gate
and the missing stdout capture, both of which would have shipped a green PR that failed its own
contract.

---

## Implementation Phases

### Phase 0 — Preconditions (measure before building)

1. **Re-run the measurement battery on the pinned host docker version**, not the plan author's
   29.4.3. Record the actual `docker-ce` version on web-1 (`deploy-status` webhook or the
   apt candidate inside `ubuntu:24.04`), then re-run each row of the discrimination table
   against it. **Any row whose string differs from this plan's table invalidates that row's
   arm** — fix the plan, do not fix the test. (learning §2.)
2. Confirm the harness extension points exist: `run_deploy_zot_login_stderr`
   (`ci-deploy.test.sh:3437`), `assert_zot_login_class` (`:3455`), the
   `MOCK_ZOT_LOGIN_FAIL_STDERR` mock arm (`:289`), and the Sentry capture file
   (`MOCK_SENTRY_CAPTURE_FILE`, `create_curl_mock` `:433-460`).
3. Confirm the suite is registered: `infra-validation.yml:344` → `bash apps/web-platform/infra/ci-deploy.test.sh`.
4. **Record the green baseline: the suite is currently 153/153** (not 22/22 — that count is from
   an earlier file). Any new test must move that denominator.

### Harness constraints (verified — these shape the test design, so read them first)

- **There is no source guard.** `ci-deploy.sh` has no `BASH_SOURCE[0]` check and no
  source-without-execute env, so **individual functions cannot be called directly**. Every test
  drives the whole script via `bash "$DEPLOY_SCRIPT"` with `SSH_ORIGINAL_COMMAND` set. The two
  sanctioned styles are **behavioural** (arm a mock, assert on the captured sink) and
  **inspection** (`awk '/^fn\(\) \{/,/^\}/' "$DEPLOY_SCRIPT"` → grep the extracted body, which is
  body-scoped so a sibling function cannot satisfy the assertion). Prefer behavioural; this
  plan's assertions are all reachable that way.
- **Mocks are PATH shims** in a per-run `MOCK_DIR`, behaviour-switched by `MOCK_*` env vars.
  `TEST_PATH_BASE` deliberately excludes `~/.local/bin` so a missing mock fails loudly instead
  of reaching the real `doppler`.
- **The GHCR mock arm is asymmetric and must be fixed symmetrically.** Today
  (`ci-deploy.test.sh:289-296`) the zot arm takes **caller-supplied** stderr and is
  **registry-scoped**:
  ```bash
  if [[ -n "${MOCK_ZOT_LOGIN_FAIL_STDERR:-}" && "$_lreg" == "10.0.1.30:5000" ]]; then …
  if [[ -n "${MOCK_GHCR_LOGIN_FAIL_TOKEN:-}" && "$_ltok" == "${MOCK_GHCR_LOGIN_FAIL_TOKEN}" ]]; then
    echo "denied: authentication required" >&2   # HARDCODED
  ```
  The zot arm's registry-scoping is load-bearing and commented as such — it must never match
  `ghcr.io` *"so arming it cannot perturb the GHCR legs the #6400/#6090 tests assert on."* The
  new `MOCK_GHCR_LOGIN_FAIL_STDERR` MUST be scoped symmetrically (`_lreg == "ghcr.io"`) or it
  will perturb those legs.
- **`refetch_ghcr_and_relogin` has inspection-only coverage today** (`:3402`, an `awk`-extracted
  `HELPER_BODY` grep for token hygiene). Phase 3 gives it its **first behavioural test** — budget
  for that, and do not assume a fixture exists.
- **The leak-canary precedent already exists — extend it, do not invent it.** T-5B-8 (`:3583`)
  and T-5B-8b (`:3600`) inject `SENTINEL_LEAK_CANARY_zot-pull` into the login stderr and assert
  it reaches **neither** the Sentry capture **nor** the journald capture
  (`MOCK_LOGGER_CAPTURE_FILE`), the latter asserted against the **whole** sink because that tag
  ships unscrubbed off-box via `vector.toml`.

  > **Vacuous-green trap — the single most important test finding in this plan.** Both existing
  > canaries drive a **401** stderr, which classifies as `authn_rejected`. The escape hatch fires
  > **only** on `unclassified`. **So the existing canaries never execute the escape hatch, and
  > would stay green while it leaks.** AC3's canary MUST route through the `unclassified` path.
  > This is exactly the shape learning §5 describes: an assertion whose name ("raw stderr never
  > reaches the sink") is broader than what it exercises.
- **`host_id` is deliberately NOT asserted at runtime** (`:3606-3613`) — `resolve_host_id` reads
  IMDS/machine-id, which mocks cannot supply, so a non-empty assert goes red on correct code;
  the guard is a body-scoped `awk` inspection instead. **Precedent to follow** if any new field
  turns out to be unsatisfiable under mocks (learning §5 companion nuance: a vacuous assert and
  an unsatisfiable assert are both wrong).
- **The suite is currently ADVISORY, not a required check** (`infra-validation.yml:339`, tracked
  by #6480). A green suite does **not** block merge. This raises the value of the mutation
  battery (AC9) — the suite is the only thing that will catch a regression here, and nothing
  forces it to run.

### Phase 1 — `stderr_chars` AND `stdout_chars`: split the empty-vs-unmatched bucket for real

Emit, for a **failed** login, the byte length of **both** captured streams.

**`stderr_chars` alone is not sufficient, and believing it was is this plan's own §5 defect
recurring one level down.** H-B is a **disjunction** — *"the error text went to stdout (which is
`>/dev/null`), **or** nowhere at all."* `stderr_chars=0` is true under **both** arms, so it
**restates** H-B rather than deciding it. Shipping only `stderr_chars` and inferring *"len=0 ⇒
capture stdout"* is an inference, not a measurement: if stdout was also empty, that remediation
ships and yields nothing — costing exactly the second telemetry PR this plan exists to prevent.

So capture stdout too — **and `rc`, which this plan measured and then dropped.** The
discrimination table has an `rc` column; every row is `rc=1` except corrupt-config (`rc=0`). `rc`
is what rescues the otherwise-terminal `stderr_chars=0 stdout_chars=0` reading, and it is an integer
from `$?` — structurally incapable of echoing input, so it is free under R2:

| rc | meaning | actionable from this field alone |
|---|---|---|
| 1 | docker ran, login rejected | no — needs `kw`/`tok` |
| 125/126/127 | docker missing / not executable / not on PATH | **yes, instantly** |
| 137 | OOM-killed mid-login | **yes** |
| 124 | `timeout` wrapper fired | **yes** |

Then: 

| reading | verdict |
|---|---|
| `stderr_chars>0` | text arrived and matched no arm → the remediation is an arm |
| `stderr_chars=0 stdout_chars>0` | **H-B-stdout** — the text went to stdout → the remediation is stream capture |
| `stderr_chars=0 stdout_chars=0` | **H-B-nowhere / H-D** — no output at all → a different investigation |

That splits H-B in **one event**.

**Security consequence, binding:** `stdout` must ride the **same** fixed-vocabulary emitter —
never a passthrough. `docker login` prints `Login Succeeded` there, and a registry may echo more.
**AC3's canary must cover stdout as well as stderr.**

Note the measured asymmetry: on **success**, stderr is non-empty (the
`WARNING! Your credentials are stored unencrypted…` notice, 192 bytes) and stdout carries
`Login Succeeded`. Irrelevant here — we classify only on failure — but it forbids any future
"stderr empty ⇒ success" shortcut.

### Phase 2 — the escape hatch (fixed-vocabulary, EVERY failed login, BOTH sites)

> **The brief specified an `unclassified`-ONLY hatch. That mechanism defeats the brief's own
> stated goal ("so this can never dead-end again") the moment Phase 4 lands, and the plan
> therefore fires the hatch on EVERY failed login.** Recorded as UC-3 in `decision-challenges.md`.
>
> **Why — the finding that nearly shipped the bug again.** Both surviving cred-store hypotheses
> share a measured prefix:
> - H-A `error saving credentials: error storing credentials - err: exec: "docker-credential-X": executable file not found in $PATH…`
> - H-C `error saving credentials: write <path>: no space left on device`
>
> Phase 4's `cred_store` arm matches `error saving credentials` — so **both** classify as
> `cred_store`, the hatch (fired only on `unclassified`) **never runs**, and H-A and H-C become
> **byte-identical in the emit**. `cred_store` would become a ≥2-mode bucket: **`unclassified`
> reproduced under a new name, in the PR whose entire purpose is to drain it.** Verified by
> running both measured strings against the proposed arm.
>
> Firing the hatch on every failed login costs nothing and is what makes `cred_store`
> splittable. This is the same lesson as learning §3 — an arm's value is (true positives − false
> positives), and an arm that *collapses* two live hypotheses has a negative one unless the hatch
> rides alongside it.

**HARD CONSTRAINT — and the correct formulation of it.** security-sentinel's 2026-07-15 ruling
established a **structural** property: every arm is a bare `printf '<literal>'`, so **no input
byte can reach a sink**. The property that makes the design sound is **not** "the allow-list is
closed" — it is:

> **No parameter expansion appears in any `printf` argument in the emitter.**

That formulation is grep-checkable, survives regex defects, survives future loosening, and is the
only form of the claim the ruling actually established. **Mandate Form B verbatim:**

```bash
# Form A — FILTER. FORBIDDEN. Input reaches the sink, gated only by a regex.
if printf '%s' "$t" | grep -qE '^(error|time|WARNING)$'; then printf '%s' "$t"   # <-- INPUT IS THE PAYLOAD
else printf 'other'; fi

# Form B — LITERAL ARMS. REQUIRED. Structurally incapable of echoing.
case "$t" in
  error*)   printf 'error'   ;;
  time=*)   printf 'time'    ;;
  WARNING*) printf 'WARNING' ;;
  Cannot*)  printf 'Cannot'  ;;
  *)        printf 'other'   ;;
esac
```

Both forms have the **same output set**. They have opposite failure modes: **Form A degrades to
disclosure, Form B degrades to a wrong label.** Under Form A the `^…$` anchoring becomes
load-bearing *for confidentiality* — and dropping an anchor is a one-character edit that **this
exact file has already shipped once** (the bare-`denied` arm the 2026-07-15 review caught).

**The pressure to break it is measured, not hypothetical.** Feeding this plan's own measured
strings through the originally-proposed exact-match allow-list:

| first token (measured) | exact-match verdict |
|---|---|
| `error:` (non-TTY — trailing colon) | `other` ← entry **dead** |
| `time="2026-07-16T08:27:00Z"` (daemon-down) | `other` ← entry **dead** |
| `WARNING!` | `other` ← entry **dead** |
| `error` (cred-store) | match |

**3 of 8 entries never fire**, including the two best H-D candidates. The first engineer seeing
`tok=other` on every real failure loosens the match to a prefix — and under Form A, loosening
`^time$` → `time*` makes the emitted value `time="2026-07-16T08:27:00Z"`: a live, unbounded input
echo shipped to a third party, **with AC3 still green** because a timestamp is not the synthetic
credential the fixture planted. Under Form B, loosening the *pattern* is free — which is what
finally makes the "unmeasured token is cheap in the hatch" principle **safe**, not just true.

So the allow-list is restated as **patterns**, not literals: `error*`, `time=*`, `WARNING*`,
`Cannot*`, `failed*`, `denied*`, `unauthorized*`, default `other`.

The hatch emits, and can only emit:

- `stderr_chars` / `stdout_chars` — integers (naming per Phase 1).
- `kw` — which of a fixed keyword set matched, each probe a `grep -q` whose *output* is a
  hardcoded token joined by `,`. Input never reaches the value.
- `tok` — the first token's **pattern class** via the Form B `case`. Never the raw word.

**`kw` must be enumerated from the MEASURED table, not the falsified list.** The originally-drafted
`kw` set contained *only* the three falsified tokens — none of which appear in H-A, H-B, or H-C's
measured strings — so `kw` would have been **empty for every surviving hypothesis** while `tok`
read `error` for both H-A and H-C. The hatch would have emitted nothing discriminating. Minimum
discriminating set, all measured:

| probe (measured literal) | discriminates |
|---|---|
| `no space left on device` | **H-C** (disk-full) |
| `executable file not found` | **H-A** (helper missing) |
| `docker-credential` | **H-A** (helper family) |
| `permission denied` | EACCES re-check (ruled out on live data — confirms if it returns) |
| `error saving credentials` / `error storing credentials` | cred-store family |
| `non-TTY device` · `Cannot connect to the Docker daemon` · `credential helper` | the three falsified tokens — **kept, because under Form B they are free**, and `kw` is exactly how we learn which was right |

> **Design principle, earned from the measurements.** An **unmeasured token is cheap in the
> escape hatch and expensive in a classifier arm** — in the hatch it never matches and the other
> fields still land; in an arm it mis-routes the operator. Direct generalization of learning §3's
> *"bare terms are cheap in a LATE arm and expensive in an EARLY one."* **This principle is only
> SAFE under Form B** — under Form A a never-matching probe invites the loosening that leaks.

**`stderr_chars` is not a leak — name the property in the code comment.** The map from token bytes
to length is **constant**: both pull tokens are fixed at 40 chars, so a registry echoing the token
moves `stderr_chars` by exactly +40 *for every possible token value*. The channel carries **zero
bits** about content, not "few bits", and does not accumulate across 6-12 deploys/day. Token
*length* is already public from the format name. The comment must state:

> *`stderr_chars` is a non-injective function of the stderr whose value is invariant under
> substitution of any fixed-length secret. It discloses shape, never content. Safe because both
> pull tokens are fixed-length (40); **if either becomes variable-length (a JWT, an OIDC-minted
> session token), this becomes a length oracle and must be bucketed** (`0 | 1-99 | 100-399 | 400+`).*

Bucketing now would destroy the empty-vs-unmatched split's precision for a risk that does not yet
exist — but the trigger must be written down.

### Phase 2b — containment and the capture primitive (both load-bearing, both MEASURED)

**(a) The dominant abort class is a NONZERO RC, not an unset variable — and `${x:-}` cannot touch
it.** This is the sharpest finding of the review round and it invalidates the plan's first draft
of R1/AC2. `grep -q` **returns 1 on a non-match**, which is the *normal* case for a probe:

```bash
set -euo pipefail
kw="$(printf '%s' "$e" | grep -q 'ZZZ' && printf 'zzz')"   # rc=1 → THE SCRIPT DIES
```

Measured: the parent shell aborts, with every variable bound. An AC that only injects unset
variables has **a hole exactly the size of this diff's most likely failure mode.**

Measured containment table:

| construct | `set -u` unbound | `set -e` nonzero rc |
|---|---|---|
| `f \|\| true` | **parent DIES** | rescued |
| `x="$(f)" \|\| true` | **parent DIES** | rescued |
| `( f ) \|\| true` | **parent survives** | **rescued** |

**Mandate the subshell:** the whole hatch is emitted as `hatch="$( ( _login_hatch … ) || true )"`.
It is the **only** construct that contains *both* abort classes, and it is what structurally
enforces the contract the Observability block already states (`fail_loud: false — a telemetry
failure must never abort a deploy`). `${x:-}`-at-every-site remains required, but it is a
**discipline**; the subshell is a **mechanism**. The 2026-07-15 control was inspection; this
plan's first draft upgraded it to behavioural verification of the discipline — which still only
verifies the discipline was *applied*, not that misapplication is *non-fatal*. The subshell makes
it non-fatal. Trade accepted: a broken hatch goes dark instead of wedging prod.

**(b) Drop the temp file: capture into a variable.** Verified — `ci-deploy.sh` contains two
divergent `mktemp` idioms, and Phase 3's new sites sit next to the **unsafe** one:

```
:889   zerr="$(mktemp)"                                              # safe (fails loud)
:950   perr="$(mktemp 2>/dev/null || echo /tmp/ci-deploy-pull.err)"  # FIXED, PREDICTABLE PATH
:1021  err="$(mktemp  2>/dev/null || echo /tmp/cosign-verify.err)"   # same
```

"Capture to a temp exactly as the zot site does" invites the `:950` template, which degrades to a
world-readable fixed path under any `mktemp` failure — while holding registry stderr that may
echo the credential. **And a bare `mktemp` is itself an abort vector under `set -e` when `/tmp` is
full — which is hypothesis H-C.** If H-C is the true cause, a `mktemp`-based instrument **wedges
prod on the first deploy after merge**, in exactly the scenario it exists to diagnose.

Use variable capture at all three sites:

```bash
local zerr zrc=0
zerr="$( ( printf '%s' "$ztoken" | docker login "$REG" -u "$zuser" --password-stdin 2>&1 >/dev/null ) )" || zrc=$?
```

Strictly better on every axis: no filesystem, no mode question, no `rm -f`, no cleanup-on-abort
gap, no predictable-path fallback, no `/tmp`-full abort. The secret-adjacent text never leaves
process memory. **It also designs out Phase 2's `tail -c 400` sharp edge and AC5 entirely** —
`${#zerr}` is the true length by construction.

Three sharp edges that MUST be stated in the code:

1. **`local zerr` and the assignment must be SEPARATE statements.** `local zerr="$(cmd)"` makes
   `local` the exit status and swallows `rc` — this is the R1 shape, and the file already knows it
   (`:824-825`).
2. **`2>&1 >/dev/null` — that order.** Reversed, it captures stdout and lets stderr through.
3. **`$(…)` strips trailing newlines, and `${#…}` counts CHARACTERS, not bytes, under a UTF-8
   locale.** Either pin `LC_ALL=C` or name the field `stderr_chars`. **The plan says
   `stderr_chars`** — calling it a "true byte length" would be the next false comment.

### Phase 3 — GHCR parity: capture + classify, reusing the renamed classifier

Both GHCR sites currently discard stderr: `ci-deploy.sh:803` (prelude) and `:746` (inside
`refetch_ghcr_and_relogin`). Reuse the **same** classifier — do not fork a second one — renamed
registry-neutral to `_docker_login_failure_class` / `_docker_login_http_status`.

> **P0 — `refetch_ghcr_and_relogin`'s STDOUT IS A TYPED CONTROL CHANNEL. Do not write to it.**
> The function communicates **by stdout string**: `printf recovered` / `refetch_unavailable` /
> `relogin_failed` (`:747`, `:749`), parsed by two callers — `:825` (`prelude_stage`) and `:925`
> (`stage="$(refetch_ghcr_and_relogin)"` → `[[ "$stage" == "recovered" ]]`). At `:829` the stage
> is interpolated **raw** into a `logger` line.
>
> Two failure modes, both from one reflexive edit:
> - **Leak:** capturing stderr with `2>&1` *at the function level* merges docker's stderr into the
>   function's stdout → into `$prelude_stage` → into **journald → Vector → Better Stack,
>   verbatim and unclassified**. AC3 inspects the *Sentry* payload and **would never see it**.
> - **Silent recovery loss:** `stage` becomes `"transport recovered"`, the `==` compare fails, the
>   #6400 recovery is discarded, and the private pull fails-closed — degrading the deploy path
>   this helper exists to protect.
>
> **Constraints, all testable:** (i) nothing inside the helper may write to stdout except the
> three stage literals; (ii) the stderr capture wraps the **`docker login` invocation only**
> (Phase 2b's form), never the function; (iii) the class is returned via a **named global**
> mirroring `RECOVERY_STAGE`, never appended to the stage string. Same shape at `:925` →
> `RECOVERY_STAGE` → `pull_failure_event`'s tag.

**Classify BOTH prelude logins, and say so.** `:803` (baked/first creds) and `:746` (post-refetch)
are two logins in one cycle. If only the second is classified, the **baked-cred failure shape is
lost** — and that shape is the #6090/#6400 recurrence signal.

**Name the Sentry event and its tags — do not reuse the zot beacon.** `zot_gate_degraded_event`
(`:699`) hardcodes `registry: "zot-gate-degraded"`, `zot_gate_reason`, and the message
*"zot gate degraded (…)"*. Routing a GHCR failure through it files a GHCR failure under a
zot-gate issue — **the exact host-attribution error this plan corrects for #6497, reintroduced.**
Rename the tags `login_class` / `login_http` and add a mandatory `registry: zot|ghcr`
discriminator (or give GHCR its own event). Update Observability `configured_in` accordingly.

> **Sentry volume — GHCR login failure is journald-only today** (`:804`, `:815`, `:829` are all
> `logger`; no Sentry). Phase 3 would create a **new Sentry emit source**, reachable ~2×/deploy ×
> 6-12 deploys/day, for an already-diagnosed failure. **Decision: emit the GHCR class to journald
> only.** Better Stack already ingests `SYSLOG_IDENTIFIER=ci-deploy`, so the class is fully
> discoverable there; a second sink buys nothing and spends the quota that real end-user error
> events need. The zot beacon's volume is pre-existing and unchanged. (This also removes the
> tag-conflation risk above at its root — revisit only if journald proves insufficient.)

### Phase 4 — arms, gated on measurement, ordered before `transport`

**`transport` is over-collecting, and `cred_store` alone does not fix it.** Measured against the
real classifier:

| shape (measured) | current class | correct |
|---|---|---|
| `error saving credentials: open <path>: permission denied` | `transport` | `cred_store` |
| ~~`Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: … connect: permission denied`~~ | ~~`transport`~~ | ~~**`cli_daemon`**~~ **ROW RETIRED** — /work Phase 0 measured that this shape **cannot occur on the login path** at all (docker login never touches the daemon socket in 29.x). Not a reclassification: a non-event. See finding 2 below. |
| `received unexpected HTTP status: 504 Gateway Timeout` | `transport` | **`server_error`** |
| `received unexpected HTTP status: 502 Bad Gateway` | `server_error` ✓ | — |

Three findings, all verified by execution:

1. **`cred_store`** — anchored **only** on measured literals `error saving credentials|error
   storing credentials|error getting credentials`. MUST precede `transport`, whose bare
   `permission denied` otherwise steals the EACCES variant.
2. ~~**`cli_daemon`**~~ — **RETIRED AT /work PHASE 0 BY THE MEASUREMENT THIS ROW DEMANDED.**
   The row's own gate was *"Discriminators, to be measured at AC1 before promotion: `docker.sock`,
   `unix://`, `_ping`. **If AC1 cannot reproduce them, they stay `kw` probes and no arm ships**
   (learning §2)."* **AC1 could not reproduce them.** Measured on 29.4.3: `docker login` **never
   contacts the daemon socket** — a dead `DOCKER_HOST=unix:///nonexistent/d.sock` yields **no
   daemon error whatsoever** on the login path, while `docker ps` on the same dead socket yields
   `failed to connect to the docker API at unix:///nonexistent/d.sock: … no such file or
   directory`. Login is CLI-side in docker 29.x. So the premise — *"the deploy user dropped from
   the `docker` group renders a daemon-socket EACCES **on the login path**"* — is false: that
   failure cannot reach this classifier at all. **No `cli_daemon` arm ships.** The three
   discriminators are demoted to `kw` probes, where an unmeasured token is free (Phase 2's design
   principle). See Research Reconciliation 10.
3. **`504` lands in `transport`, not `server_error`** — `transport` (`:669`) precedes
   `server_error` (`:671`) and carries a bare `timeout` matched case-insensitively, so
   `504 Gateway Timeout` matches `timeout` first. An interposed-proxy 5xx routes the operator to
   the network. `502`/`503` are unaffected — only the timeout-worded 5xx bite. Fix by ordering
   `server_error` before `transport`, or by anchoring `transport`'s timeout terms; **pin whichever
   with a test fed the measured 504 string.**

**On "ordering is load-bearing" (learning §3 calls this a red flag, not a defense) — the objection
is correct and is met, not dodged.** The overlap is real and measured, so the arms are genuinely
not disjoint on real input. The resolution is precedence *plus* two things the 2026-07-15 draft
lacked: (i) every precedence relation is **pinned by a test fed a measured string**, so a reorder
goes RED rather than silently mis-routing; and (ii) **the hatch now rides every failed login**
(Phase 2), so a confidently-wrong arm is **visible in production telemetry** (`class=transport
kw=credentials` is self-evidently wrong the moment it appears) rather than discoverable only from
the test suite. That second property is what makes the arms auditable at all — and it is why the
`unclassified`-only gate had to go.

**Not added** (per Research Reconciliation 1-3): `not a TTY`, `credential helper`,
`Cannot connect to the Docker daemon`. All three were falsified or unreproduced. They go in the
`kw` probe set, where being wrong is free.

### Phase 5 — comment truth-up (learning §Session-Error-13)

A diff that changes a behaviour must re-read the comment that justifies that behaviour.
Each of these is falsified **by this diff or by the 08:15Z experiment**:

- `ci-deploy.sh:652-655` — *"Ordering is therefore NOT load-bearing for correctness anymore
  (the arms are disjoint on real input)"* → **falsified by Phase 4**. Must state the overlap and
  name the test that pins it.
- `ci-deploy.sh:648-650` — the H4 note referencing "the plan"; re-point at this plan.
- **`ci-deploy.sh:636-647` — falsified by the RENAME, not by the diff's logic, which is why it is
  the easiest to miss.** The block justifies `authz_denied`'s narrowness with a **zot-specific
  measurement**: *"MEASURED against the pinned zot (v2.1.2) … answers 200 or 401 — **NEVER 403** …
  `authz_denied` is effectively unreachable here … kept, narrowed, purely as a defensive
  tripwire."* **GHCR can and does answer 403** (SAML/SSO enforcement, org package policy, IP
  allow-lists). The moment the classifier is registry-neutral, *"unreachable here"* and *"purely a
  defensive tripwire"* become **false statements about a live arm** — in the same comment block as
  the reasoning this plan exists to correct. Same for consequence `2.` (*"A BROKEN accessControl is
  NOT observable here at all"*), which has no GHCR meaning. **Fix:** split into a registry-neutral
  preamble (the `status:` anchor + the enum contract — both dockerd behaviours, genuinely
  registry-agnostic) and a `## Per-registry measured behaviour` subsection with a `zot v2.1.2:`
  paragraph and a `ghcr.io:` paragraph. **The GHCR paragraph must say `unmeasured`** unless AC1
  measures it — inheriting zot's finding for a registry whose strings were never measured is
  precisely this plan's central discipline, violated.
- **`ci-deploy.sh:643-644`** — *"`connect: permission denied` is a SOCKET error (ICMP
  admin-prohibited → EACCES)"* conflates ICMP-admin-prohibited EACCES with **unix-socket** EACCES
  because both render `connect: permission denied`. Phase 4's `cli_daemon` arm makes this comment
  an assertion that the *network* reading is correct for a shape that is now classified as local.
- `ci-deploy.sh:725-750` + `:762-763` — `refetch_ghcr_and_relogin` / prelude headers assert
  stderr handling that Phase 3 changes.
- `zot-registry.tf:108-109` and `:332` — assert the htpasswd edge **was** WEB-PLATFORM-5B.
  **Falsified.** Narrow to what is true: the edge closes a real rotation-convergence gap; the
  claim that this gap caused WEB-PLATFORM-5B was refuted by the 08:15Z re-bake. Delete the false
  claim, do not contradict it in an adjacent sentence.
- The `2026-07-15` learning's `## Problem` states the htpasswd cause as fact. Add a dated
  addendum — its **lesson** is untouched, its **root cause** is refuted, and a learning asserting
  a falsified cause compounds the exact class it documents. (3 lines; not a rewrite.)

### Phase 6 — issue hygiene

1. **Re-title #6497** →
   `P1: zot/GHCR docker-login gate cannot name its own failure — class=unclassified is ≥4 modes (WEB-PLATFORM-5B)`.
   Add a comment recording: the htpasswd hypothesis was falsified by run 29482827061; AC10 is
   green and AC11 is **red**, exactly as the issue body predicted AC10 would not be sufficient;
   the surviving decomposition is unchanged (condition 1 of 3 still unmet, now for a different
   reason).
2. **Comment on #6416** (CLOSED 2026-07-16) — its title claimed *"ADR-096 zot-primary dead
   end-to-end"* but its gate (`scripts/followthroughs/zot-mirror-connector-6416.sh`) measured
   only the **CI push** path: every anchor is `127.0.0.1:5000` from inside the runner, and it
   never observes a pull. Closing on 5/5 proves zot is **written to**, not that the round trip
   lives. The closure is legitimate for its true scope (condition 2 of 3: zot holds the tag); the
   **title** over-claimed. Point at #6497 + #6122 as the surviving end-to-end trackers.
   **Do not reopen** — the soak genuinely passed what it measured.
3. **File the repair follow-up** (brief §D — explicit, not implicit): *"decide and repair the
   cause of the GHCR/zot docker-login failure once the gate self-reports"*, blocked on this PR,
   with the surviving hypotheses H-A..H-D and the measured table.
4. **#6500 stays distinct.** Real, separate, not the cause of these events. Not folded in.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | Phases 1-5. Rename classifier registry-neutral; `cred_store` arm before `transport`; capture+classify both GHCR sites; `stderr_chars`/`kw`/`tok` escape hatch at both sites; comment truth-up. |
| `apps/web-platform/infra/ci-deploy.test.sh` | New cases + `assert_ghcr_login_class` + `MOCK_GHCR_LOGIN_FAIL_STDERR` mock arm; mutation battery. |
| `apps/web-platform/infra/zot-registry.tf` | **Comment-only.** Two falsified causal claims (`:108-109`, `:332`). |
| `knowledge-base/project/learnings/2026-07-15-false-comment-…-restated-it.md` | 3-line dated addendum: root cause falsified; lesson stands. |
| `knowledge-base/project/specs/feat-one-shot-6497-login-gate-unclassified/decision-challenges.md` | The successor-issue User-Challenge (headless path). |

**Files NOT to edit — with reasons, because a silent exclusion is not a scope decision:**

- `cloud-init-registry.yml`, `zot-disk-heartbeat.sh`, ADR-115 — the htpasswd edge and its probe
  are correct and converged; only their *causal attribution* is wrong, and that lives in comments.
- **Four further `docker login … >/dev/null 2>&1` sites are deliberately out of scope.** The
  contract *"the docker-login gate can name its own failure"* does not reach them in this PR:
  `soleur-host-bootstrap.sh:207` (GHCR) and `:231` (zot); `cloud-init.yml:507` (zot);
  `cloud-init-inngest.yml:260` (GHCR). **Reason:** the observed failure is on the **deploy** path;
  these are **boot**-path, and a change to `cloud-init*.yml` forces a host replace
  (`hr-prod-host-config-change-immutable-redeploy`) — a blast radius this observability PR must
  not carry. **Recorded for the follow-up:** `soleur-host-bootstrap.sh:224` already fires a Sentry
  beacon *"fresh-boot zot docker login failed"* **with no class field** — the same undifferentiated
  bucket #6497 exists to drain, on the fresh-boot path, **with the sink already wired**. It is the
  cheapest next application of this plan's classifier and belongs in the follow-up issue (Phase 6.3).

---

## Infrastructure (IaC)

**Apply path — verified by the right question, not by a `-target` grep** (learning §6, which is
about *this issue* prescribing exactly the grep that passed while its conclusion was false):

- **`ci-deploy.sh` ships on merge. No dispatch, no operator step.** Evidence:
  `apply-deploy-pipeline-fix.yml` is `on: push: branches:[main]` (`:62-64`) with `paths:`
  including `apps/web-platform/infra/ci-deploy.sh` (`:66`). Its `apply` job (`:183`) has
  `needs: preflight` + `if: needs.preflight.outputs.skip != 'true'` — a **commit-message
  kill-switch only**, not a `workflow_dispatch` gate. It applies
  `-target=terraform_data.deploy_pipeline_fix` (`:288`), which POSTs the file through the CF
  Tunnel to `/hooks/infra-config`. The merge **is** the authorization.
- **The `zot-registry.tf` edit is comment-only and applies nothing — by two independent
  mechanisms.** (1) Every resource in that file is an `OPERATOR_APPLIED_EXCLUSION`
  (`zot-registry.tf:15-21`, CTO ruling 2026-07-06) and is absent from the per-PR `-target=` list,
  so the `apply-web-platform-infra.yml` run this merge triggers (`paths: apps/web-platform/
  infra/*.tf`) targets none of it. (2) A comment changes no attribute, so `terraform plan` yields
  no diff regardless. **State it in the PR body** rather than claiming "no infra impact" — the
  workflow does fire, and it does nothing.
- **No host replace.** `terraform_data.deploy_pipeline_fix` is a file-push via `local-exec`, not
  an `hcloud_server` replace. This matters for AC design: delivering the instrument does **not**
  reset web-1's docker config, so — unlike the htpasswd probe (learning §7) — **this instrument
  has a valid "before"** and its first reading observes the live failure state.
- `hr-prod-host-config-change-immutable-redeploy` is satisfied: the change ships via Terraform,
  not an in-place SSH edit.

---

## Observability

```yaml
liveness_signal:
  what: ZOT_GATE (zot) + PRELUDE (ghcr) journald lines carrying rc + class + stderr_chars +
        stdout_chars + kw + tok for EVERY failed login on BOTH registries; the WEB-PLATFORM-5B
        Sentry beacon carries the same for the zot gate only (GHCR is journald-only by choice —
        see Phase 3 Sentry-volume note)
  cadence: every deploy (~6-12/day observed)
  alert_target: Sentry WEB-PLATFORM-5B (existing issue); Better Stack source
                soleur-inngest-vector-prd (label; the emitting host is soleur-web-platform)
  configured_in: apps/web-platform/infra/ci-deploy.sh — zot_gate_degraded_event (Sentry beacon,
                 bespoke curl to the store endpoint) and the PRELUDE/ZOT_GATE logger lines
                 (journald -> Vector). These are TWO INDEPENDENT TRANSPORTS with independent
                 failure modes; do not read one as evidence for the other.
error_reporting:
  destination: journald (both registries) + Sentry store endpoint (zot gate only)
  fail_loud: false — fail-open by design; a telemetry failure must never abort a deploy.
             STRUCTURALLY enforced by the Phase 2b subshell, not only by ${x:-} discipline
             (set -euo pipefail; see Risks R1)
failure_modes:
  - mode: GHCR login fails, cause unknown
    detection: PRELUDE line carries rc + class + stderr_chars (was: stderr silently discarded)
    alert_route: journald -> Vector -> Better Stack (--grep PRELUDE)
  - mode: login fails with a stderr matching no arm
    detection: class=unclassified + stderr_chars>0 + kw/tok naming the shape
    alert_route: Sentry WEB-PLATFORM-5B (zot) / Better Stack (ghcr)
  - mode: login fails with NO stderr at all (H-B)
    detection: stderr_chars=0 + stdout_chars>0 => text went to stdout;
               stderr_chars=0 + stdout_chars=0 => no output at all, and rc names it
               (127 docker absent / 137 OOM / 124 timeout) - the split Phase 1 delivers
    alert_route: Sentry WEB-PLATFORM-5B (zot) / Better Stack (ghcr)
  - mode: a CONFIDENTLY-WRONG arm (cred-store EACCES, daemon-socket EACCES, 504) misroutes
          the operator to the wrong subsystem
    detection: the hatch rides EVERY failed login, so class=transport kw=credentials is
               self-evidently wrong in production; each precedence relation is pinned by a
               test fed a measured string
    alert_route: Sentry WEB-PLATFORM-5B (tag login_class) / Better Stack
logs:
  where: journald on web-1 (SYSLOG_IDENTIFIER=ci-deploy, allowlisted in vector.toml:130)
         -> Vector -> Better Stack
  retention: remote() is a ~40-min hot window. VERIFIED - betterstack-query.sh mode 2 already
             UNIONs remote() with s3Cluster(primary, <_s3>), so THE ARCHIVE ARM IS THE DEFAULT;
             --no-archive opts OUT. Never pass --no-archive for a soak-length span.
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    --since 60m --grep ZOT_GATE --grep PRELUDE
  expected_output: >
    a ZOT_GATE line AND a PRELUDE line, each carrying rc= and class=; when
    class=unclassified, a populated stderr_chars= / stdout_chars= / kw= / tok=. NO ssh.
```

> **Both of the first draft's commands were malformed — verified against the script's own
> parser.** `--since` matches `^([0-9]+)([hmd])$`; a bare `60` **fails the regex** and falls
> through to the literal branch → `WHERE dt >= '60'`, which ClickHouse cannot read as a DateTime.
> **The plan's one no-SSH probe did not execute.** Fixed to `60m` / `90m`. Verified flag list:
> `--since --until --grep --limit --raw-only --no-archive --table --table-s3`.
>
> **And `--grep ZOT_GATE` alone cannot see half the deliverable** — GHCR failures emit `PRELUDE:`
> lines, which contain no `ZOT_GATE` substring (verified: zero co-occurrences in the file). Phase
> 3's entire GHCR parity would have been unverifiable post-merge by the plan's only probe.
> `--grep` is repeatable and OR-combined.

**Field placement — `stderr_chars` goes in `extra`/context, NOT `tags`.** An unbounded-cardinality
integer as a Sentry **tag** degrades the tag index and decays search on the very issue this PR
exists to make searchable. The empty-vs-unmatched split needs only `len=0` vs `len>0`; the precise
value is diagnostic context, not a facet. Keep `login_class` / `login_http` / `registry` as tags.

**The registry host is deny-all/no-SSH.** Every step here is Better Stack + Sentry + `gh`.
No step asks the operator to fetch, paste, or eyeball anything
(`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-no-ssh-fallback-in-runbooks`).

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — AMENDED at /work Phase 0 (Research Reconciliation 9); the original wording was
  falsified.** There is **no pinned host docker version** to re-measure on:
  `cloud-init.yml:428` installs `docker-ce` **unpinned**, web-1 has not been replaced since
  2026-03-17, and its docker version is **not observable in any current telemetry**. AC1 is
  therefore restated as:

  > The arms cite strings **measured on docker 29.4.3** (plan author + implementer, both
  > measured independently, against a live `registry:2`); the host's version is **not pinned and
  > not currently observable**, so the instrument **emits `docker_ver`** on every failed-login
  > telemetry line and the follow-up issue (Phase 6.3) records the first observed host value.
  > **Any arm whose literal does not appear in the host's measured output is amended then.**

  Re-measured on 29.4.3 at Phase 0 — **every surviving row reproduced byte-for-byte**
  (helper-missing, disk-full, cred-EACCES, non-TTY, 401, 504, corrupt-config `rc=0`, and the
  success path's 192-char stderr). **One row did not reproduce and its arm was dropped**
  (`cli_daemon` — Research Reconciliation 10).
  *(Falsifier: an arm whose literal appears in no measured output.)*
- **AC2 — `set -euo pipefail` survival against BOTH abort classes, verified behaviourally.**
  Two injections, because the first draft of this AC covered only one and **missed the dominant
  one**:
  - **(a) unset-variable injection** — each new variable unset in turn. `${x:-}` at every
    expansion site; `||` does not rescue an expansion error under `set -u` (learning §1).
  - **(b) nonzero-rc injection** — force each `grep -q` probe to **not match** (its normal case)
    and each `mktemp`/`wc` to fail. **Measured: `kw="$(… | grep -q 'ZZZ' && printf 'zzz')"` aborts
    the script under `set -euo pipefail` with every variable bound.** `${x:-}` cannot touch this.
  - **(c) structural containment** — the hatch is emitted from a subshell (`( … ) || true`),
    the only construct measured to contain *both* classes.

  In all cases the telemetry line must still render and the script must not abort.
  *(Falsifier: remove the subshell → (b) aborts the run → RED.)*

  > **Surface (verified — there is no ubuntu:24.04 container precedent in this repo).** The brief
  > says "verify on ubuntu:24.04, the shipped host image." The existing behavioural surface that
  > satisfies this is `infra-validation.yml`'s `deploy-script-tests` job, which already
  > `runs-on: ubuntu-24.04` — the same major as `server.tf:111` (`image = "ubuntu-24.04"`). Bash
  > version parity is what `set -u` survival turns on, and the runner has it. **Do not** add a
  > net-new `docker run --rm ubuntu:24.04` leg for AC2 — zero repo precedent exists
  > (`FROM ubuntu` / `container: ubuntu` / `docker run … ubuntu` all return zero hits), and the
  > runner is the sanctioned surface. AC1 is different: it turns on the **docker version**, which
  > the runner does *not* share with the host, so AC1 keeps its container/host reading.
- **AC3 — the escape hatch cannot echo its input, asserted THROUGH THE UNCLASSIFIED PATH.**
  Extend the existing `SENTINEL_LEAK_CANARY` precedent (T-5B-8 `:3583` Sentry, T-5B-8b `:3600`
  journald) with a case whose stderr **matches no arm**, so the canary actually executes the
  escape hatch. Assert the canary reaches **neither** sink, and that every emitted `kw`/`tok`
  value is a member of the closed allow-list.

  > **Load-bearing.** Both existing canaries drive a 401 (`authn_rejected`). The hatch fires only
  > on `unclassified`. **The existing canaries do not exercise it and would stay green while it
  > leaks.** Assert against the **whole** journald capture, not a prefix — that sink ships
  > unscrubbed off-box via `vector.toml`.
  > *(Falsifier: any input byte reaching either payload.)*
- **AC4 — `stderr_chars` splits the bucket.** Two cases: empty stderr → `class=unclassified
  stderr_chars=0`; unmatched non-empty stderr → `class=unclassified stderr_chars=<true length>`.
  Assert the two payloads **differ**. *(Falsifier: identical payloads — today's behaviour.)*
- **AC5 — `stderr_chars` is the TRUE length, not the truncated one.** Feed a >400-byte stderr;
  assert `stderr_chars` > 400. *(Falsifier: saturation at 400.)*
- **AC6 — `cred_store` precedes `transport`, pinned by the measured string.** Feed
  `error saving credentials: open /home/deploy/.docker/config.json123: permission denied`;
  assert `cred_store`, **not** `transport`. *(Falsifier: reordering the arms → RED.)*
- **AC7 — GHCR parity, asserted as the INVARIANT and in the POSITIVE form.** The first draft
  (`… | grep -c '2>&1'` → `0`) was a **proxy** and had two defects: (i) a regression written as
  `2>/dev/null`, or a login with no redirect at all, **passes it**; (ii) it is not comment-aware,
  so Phase 5's mandated comment rewrites — which must mention `docker login` and the removed
  `>/dev/null 2>&1` on one line — make it go **RED on a correct diff**. Assert instead, over
  non-comment lines only:
  ```bash
  L=apps/web-platform/infra/ci-deploy.sh
  # every docker login captures stderr into a variable: count MUST equal the login-site count (3)
  git grep -n 'docker login' -- "$L" | grep -v '^\s*[0-9]*:\s*#' | grep -c '2>&1 >/dev/null'   # → 3
  git grep -n 'docker login' -- "$L" | grep -v '^\s*[0-9]*:\s*#' | grep -c '>/dev/null 2>&1'   # → 0
  ```
  The count form also catches a **fourth** login site added later with no capture — which the
  negative form never would.
- **AC8 — the GHCR class rides the PRELUDE lines and the Sentry event**, asserted via a new
  `assert_ghcr_login_class` mirroring `assert_zot_login_class` (`:3458`).
- **AC9 — mutation battery, each proven RED before green** (learning §5: *mutate a sibling
  attribute IN, not just the anchor OUT*; **relocation**, not deletion):
  - Move `cred_store` **after** `transport` → AC6 RED.
  - Replace `stderr_chars` with the `tail -c 400` length → AC5 RED.
  - Swap the `tok` allow-list for a raw first-token passthrough → AC3 RED.
  - Point `assert_ghcr_login_class` at the **zot** payload → AC8 RED (proves the assert is
    body-scoped and not satisfied by a sibling emit — the `:1076` precedent).
  - **Every new assertion must be shown RED before green.** The 2026-07-15 suite was 22/22 green
    while three assertions were vacuous.
- **AC10 — no false comment survives the diff.** For every comment in the diff's hunks asserting
  a *behaviour* or *security* property, the property holds. Specifically `ci-deploy.sh:652-655`
  no longer claims ordering is not load-bearing, and `zot-registry.tf` no longer claims the
  htpasswd edge was WEB-PLATFORM-5B. *(Falsifier: `git grep -n 'WEB-PLATFORM-5B' zot-registry.tf`
  returning a line that asserts causation.)*
- **AC11 — #6497 re-titled** and the falsification comment posted;
  **#6416 carries the push-side-only correcting comment**; the repair follow-up issue exists and
  is referenced from the PR body.
- **AC12 — full suite green:** `bash apps/web-platform/infra/ci-deploy.test.sh`.

### Post-merge (automatic — no operator step)

- **AC13 — the gate self-reports on the next deploy.** Within one deploy cycle of the merge:
  ```
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
    --since 90m --grep ZOT_GATE --grep PRELUDE
  ```
  Every login outcome observed **must** fall into exactly one of three named states:

  | # | state | required shape |
  |---|---|---|
  | (a) | **success** | `ZOT_GATE: active …` / `PRELUDE: … ok` — no class field; the gate had no failure to name |
  | (b) | **no login attempted** | `reason=probe_unreachable` or `reason=creds_absent` — a bounded, named non-login state |
  | (c) | **login failed** | carries `rc` + `class` + `stderr_chars` + `stdout_chars`, and when `class=unclassified`, populated `kw`/`tok` |

  Only **(c)** is the invariant under test. **(a)** and **(b)** are "the gate had no login outcome
  to name," which is itself a bounded, named state.

  > **The first draft of this AC was RED on correct code** — the exact trap its own callout box
  > warns about, one level up. Its condition was *"a class other than `unclassified`, or
  > `unclassified` with `stderr_chars`"*. But the **success** path (`:892`) emits
  > `ZOT_GATE: active — docker login … ok (zot-primary)` with **no `class=` field at all**, and
  > `probe_unreachable`/`creds_absent` (`:872`, `:881`) return **before** the login. None of the
  > three satisfies either disjunct. R5's claim that AC13 is "green under every hypothesis
  > including recovery" was **false as written**; the three-way restatement makes it true.
  >
  > **Still deliberately NOT `class == cred_store`** — that asserts a *proxy for a hypothesis*
  > rather than *the invariant this PR delivers*. And note the first draft was **also vacuous on
  > the other side**: `class=cred_store` with zero hatch fields would have passed it, while the PR
  > failed its own contract. Requiring the hatch on every failed login (Phase 2) is what closes
  > both halves.

- **AC14 — the datum is recorded on the follow-up issue** (Phase 6.3), closing the loop from
  measurement to repair.

**Explicitly out of scope — the repair itself.** We do not yet know the cause; a guess ships to
every web host. This PR buys the datum. Filed, not implied (Phase 6.3).

---

## Open Code-Review Overlap

**None.** Verified: `gh issue list --label code-review --state open --limit 200` (62 open) →
`jq` filter for bodies containing `ci-deploy.sh` returned zero matches.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** carried forward from the measurement evidence in this plan.
**Assessment:** Scoped observability change to one shell script on an already-provisioned
surface. No new infrastructure, no new vendor, no new persistent process, no schema. The single
architectural question — *does this merge apply?* — is resolved in Infrastructure (IaC) with the
enclosing-job + trigger evidence learning §6 demands. Risk concentrates in `set -euo pipefail`
survival (R1) and the no-echo property (R2); both carry dedicated ACs and a mutation battery.

**Product/UX Gate:** not applicable — no UI surface in Files to Edit. Mechanical UI-surface
override did not fire.

**GDPR / Compliance Gate (Phase 2.7):** No regulated-data surface (no schema, migration, auth
flow, or API route). None of triggers (a)-(d) fire: no LLM/external-API processing of
operator-session data, no new artifact-distribution surface, no cron reading `learnings/` or
`specs/`. **However**, the `single-user incident` threshold is declared, and the change touches a
**credential-adjacent** emit path to a third-party sink (Sentry). That risk is carried by AC3
(no-echo) + R2 rather than by a compliance write. Skipped.

## Architecture Decision (ADR/C4)

**Skipped — no architectural decision.** A bug fix on an existing surface: no ownership/tenancy
boundary, no new substrate or integration pattern, no resolver/dispatch/trust-boundary change, no
divergence from an existing ADR. ADR-096 (zot-primary) and ADR-115 (boot-baked convergence) are
unchanged by this plan — including ADR-115, whose *rule* survives the falsification of the
*hypothesis* that motivated it.

**C4 completeness check** (all three of `model.c4`, `views.c4`, `spec.c4` reviewed, per the
mandate — not a keyword grep). Enumerated for this change: **external human actors** — none
added (no user-facing surface). **External systems** — GHCR and Sentry are the only third parties
touched; both already modeled, and neither gains or loses an edge (the beacon already POSTs to
Sentry; the GHCR login already exists — this diff changes only what it *reports*).
**Containers/data stores** — zot registry and web-1 already modeled; no store touched.
**Access relationships** — unchanged; no actor gains access to any surface. Verdict: **no C4
impact**, because the diff adds fields to an existing emit on an existing edge.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| **R1** | The hatch aborts the deploy under `set -euo pipefail`. **Two distinct classes, and the first draft named only one.** (a) an unbound expansion (the 2026-07-15 #1 P1); (b) **a nonzero rc — `grep -q`'s normal non-match, a `mktemp` on a full `/tmp` (= hypothesis H-C!), a `wc` on an unreadable file.** (b) is the *more likely* class here and `${x:-}` cannot touch it. | **Structural, not disciplinary:** emit the hatch from a subshell — `( _login_hatch … ) || true` — the only construct **measured** to contain both classes. `${x:-}` at every site remains required but is a discipline, not a mechanism. Phase 2b drops `mktemp` entirely (variable capture), removing (b)'s worst instance: an instrument that wedges prod in the exact scenario it exists to diagnose. AC2 injects **both** classes. |
| **R2** | The escape hatch becomes a passthrough and ships a credential/username to Sentry. | Fixed-vocabulary emitter: `kw` probes are `grep -q` → hardcoded literal; `tok` is a closed allow-list with `other` as default. AC3 + the mutation that swaps in a raw passthrough → RED. |
| **R3** | The `cred_store` arm is built on an unmeasured string and never fires — decoration, and CI can never fail on an arm that never fires (learning §2/§3). | Arms cite only measured literals. The three falsified tokens are demoted to `kw` probes, where being wrong costs nothing. AC1 re-measures on the pinned version. |
| **R4** | Reordering arms silently regresses `transport`'s live coverage — it is the arm that fires most on this fleet (#6415 private-NIC → `network is unreachable`; zot OOM → `connection reset`). | `cred_store`'s literals are `error {saving,storing,getting} credentials` — disjoint from every transport shape **except** via `permission denied`, which is exactly the overlap the reorder exists to resolve. The existing T-5B-5b..5f transport cases must stay green (AC12). |
| **R5** | The bug is transient and the next deploy shows no failure → AC13 unverifiable. | AC13 asserts the **invariant** (the gate names its outcome), not a **cause**. **Correction: the first draft's AC13 was RED on recovery** — the success path emits no `class=` field, so "a class other than unclassified" matched nothing. The **three-way** restatement (success \| no-login-attempted \| classified-failure) is what actually makes this mitigation true. |
| **R6** | `head`-truncated or line-scoped greps produce a false "absent" claim (plan-skill sharp edge). | AC7 uses a login-line-scoped grep with an explicit count, not a file-wide `grep -c`, and not `head`-truncated. |

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Repair the credential store now (chmod/recreate `/home/deploy/.docker/config.json`, drop `credsStore`) | **Rejected.** The cause is unknown; the EACCES variant is already ruled out by live data. A guess ships to every web host. Filed as Phase 6.3. |
| Emit the raw stderr, bounded to N bytes | **Rejected.** Destroys the structural no-echo property security-sentinel ruled on. A length-capped passthrough is still a passthrough. |
| Fork a GHCR-specific classifier | **Rejected.** Two classifiers drift. Rename the existing one registry-neutral. |
| Add arms for all five brief-proposed tokens | **Rejected — three are falsified by measurement.** They become `kw` probes. |
| Open a successor "zot serves zero pulls" issue | **Rejected as duplicate** — #6497 and #6122 already own it. Recorded as a User-Challenge; operator intent met via the #6416 correcting comment. |
| Reopen #6416 | **Rejected.** Its soak genuinely passed what it measured; only its title over-claimed. A comment corrects the record. |

---

## Downtime & Cutover

**None.** No host replace, no service restart, no schema change. `terraform_data.
deploy_pipeline_fix` pushes a file through the CF Tunnel; the next deploy picks it up. The
`apply` job shares the `web-1-swap` concurrency group, so it cannot race a release. Fail-open
throughout: every new emit path is best-effort and cannot abort a deploy (R1).
