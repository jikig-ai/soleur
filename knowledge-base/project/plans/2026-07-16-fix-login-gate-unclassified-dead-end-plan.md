# fix: drain the `unclassified` dead-end in the zot/GHCR docker-login gate (#6497)

---
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 6497
date: 2026-07-16
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

All measurements run 2026-07-16 against `docker` CLI 29.4.3 (host apt candidate on
ubuntu-24.04 is `29.1.3-0ubuntu3~24.04.2`; cloud-init installs `docker-ce` — **re-measure on
the pinned host version at /work Phase 0**, see AC1). Method: a live `registry:2` on
`localhost:15999` (answers `/v2/` 200) so the login reaches the credential-store write, which
only happens **after** auth succeeds. Measured strings were then fed through the **real**
`_zot_login_failure_class` extracted from `ci-deploy.sh:661-676`.

| # | Brief's claim | Measured reality | Plan response |
|---|---|---|---|
| 1 | §C: add arm matching `not a TTY` | **FALSIFIED.** Real string is `error: cannot perform an interactive login from a non-TTY device` — lowercase, hyphenated. `not a TTY` **never matches**. | Token dropped. Only measured literals become arms. |
| 2 | §C: add arm matching `credential helper` | **FALSIFIED.** The phrase never appears. Helper failures render `error storing credentials - err: exec: "docker-credential-<name>": executable file not found in $PATH`. | Token dropped. |
| 3 | §C: add arm matching `Cannot connect to the Docker daemon` | **NOT REPRODUCED** on the login path. A dead `DOCKER_HOST` socket rendered `time="…" level=info msg="Error logging in to endpoint, trying next endpoint"`. | Token dropped — unmeasured. Escape hatch covers it instead. |
| 4 | §3: leading hypothesis = credential-store WRITE fails (`/home/deploy/.docker/config.json`, UID 1000) | **PARTIALLY FALSIFIED BY LIVE DATA.** The *permission* variant renders `error saving credentials: open <path>: permission denied` → contains `permission denied` → the **existing `transport` arm already matches it**. We observe `unclassified`, so the EACCES variant is **ruled out**. Only the *helper* variant survives — or a mode nobody has listed. | Hypothesis narrowed (see Hypotheses). The plan does **not** build for a specific cause. |
| 5 | §3: `class=unclassified http=none` implies stderr text that matched no arm | **INCOMPLETE.** An **empty** stderr *also* renders exactly `class=unclassified http=none` (`_zot_login_failure_class "" → unclassified`). The gate cannot distinguish "text matched nothing" from "no text at all" — different bugs, different fixes. | **This is the highest-value field in the escape hatch.** `stderr_len` is decisive, not decorative. |
| 6 | §"ISSUE HYGIENE": open a successor issue for "zot serves zero pulls, not achieved end-to-end" | **DUPLICATE.** #6497's own body already states *"zot has served **zero pulls in 90 days**"* and owns the 3-condition decomposition. #6122 (umbrella) is OPEN and owns end-to-end. | **User-Challenge** — recorded in `decision-challenges.md`. Operator intent satisfied via a correcting comment on #6416 instead. |
| 7 | §"CONSTRAINTS": "ci-deploy.sh is NOT an `OPERATOR_APPLIED_EXCLUSION` — ships on merge" | **TRUE, and now verified by the right question** (learning §6). Not because it is a `.sh`: because `apply-deploy-pipeline-fix.yml` is `on: push: branches:[main]` with `paths:` including `apps/web-platform/infra/ci-deploy.sh` (`:66`), and its `apply` job (`:183`) is gated only by a commit-message kill-switch — **not** `workflow_dispatch`. | Recorded with the enclosing-job + trigger evidence, per learning §6. |
| 8 | §1: "#6497's ORIGINAL cause is FIXED AND CONVERGED" | **IMPRECISE — it was FALSIFIED, not fixed.** See below. | Drives the re-title and the PR body. |

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

**If this lands broken, the user experiences:** a wedged deploy pipeline. `ci-deploy.sh` runs
under `set -euo pipefail`; an unbound variable in the new emitter aborts the whole script, and
prod freezes on the running tag with no new release able to land (the #6400 shape: prod pinned
for ~10h). The 2026-07-15 review's **#1 P1 was exactly this** — a probe whose bare expansion
took the entire telemetry line dark, and the `unknown` guards written for that case sat 8 lines
below the line that already killed the script.

**If this leaks, the user's credentials are exposed via:** the Sentry beacon. `docker login`
stderr can echo a **username**, and some registries echo the attempted credential. An escape
hatch implemented as a passthrough would ship that to a third-party sink on every failed deploy,
retained and searchable.

**Brand-survival threshold:** `single-user incident`.

Consequences, both binding: `requires_cpo_signoff: true`, and `user-impact-reviewer` runs at
review time. Per learning §9, the 5-agent panel is the control that actually works here.

---

## Implementation Phases

### Phase 0 — Preconditions (measure before building)

1. **Re-run the measurement battery on the pinned host docker version**, not the plan author's
   29.4.3. Record the actual `docker-ce` version on web-1 (`deploy-status` webhook or the
   apt candidate inside `ubuntu:24.04`), then re-run each row of the discrimination table
   against it. **Any row whose string differs from this plan's table invalidates that row's
   arm** — fix the plan, do not fix the test. (learning §2.)
2. Confirm the harness extension points exist: `run_deploy_zot_login_stderr`
   (`ci-deploy.test.sh:3434`), `assert_zot_login_class` (`:3458`), the
   `MOCK_ZOT_LOGIN_FAIL_STDERR` mock arm (`:3445`), and the Sentry capture file
   (`MOCK_SENTRY_CAPTURE_FILE`).
3. Confirm the suite is registered: `infra-validation.yml:344` → `bash apps/web-platform/infra/ci-deploy.test.sh`.

### Phase 1 — `stderr_len` first: split the empty-vs-unmatched bucket

The single decisive field. Emit, for a **failed** login only, the byte length of the captured
stderr. `len=0` ⇒ the error text never reached stderr and the remediation is *capture stdout*;
`len>0` ⇒ text arrived and matched no arm, and the remediation is an arm. Today both render
identically and no amount of arm-adding distinguishes them.

Note the measured asymmetry: on **success**, stderr is non-empty (the
`WARNING! Your credentials are stored unencrypted…` notice, 192 bytes). Irrelevant here — we
classify only on failure — but it forbids any future "stderr empty ⇒ success" shortcut.

### Phase 2 — the escape hatch (fixed-vocabulary, `unclassified`-only, BOTH sites)

**HARD CONSTRAINT (preserve, do not weaken).** security-sentinel's ruling on the 2026-07-15 PR
was that the classifier is *structurally incapable* of echoing its input: every arm is a bare
`printf '<literal>'`. The escape hatch **must be a fixed-vocabulary emitter, not a passthrough.**
It emits, and can only emit:

- `stderr_len` — an integer.
- `kw` — which of a **fixed** keyword set matched, rendered as literals joined by `,`. Each
  probe is a `grep -q` whose output is a hardcoded token; input never reaches the value.
- `tok` — the first token, drawn from a **closed allow-list** (`error`, `Error`, `time`,
  `Cannot`, `WARNING`, `failed`, `denied`, `unauthorized`), rendering `other` for anything else.
  **Never the raw first word** — a raw first token from an unknown message is a passthrough with
  a length limit, which is the property we are forbidden to lose.

> **Design principle, earned from the measurements.** An **unmeasured token is cheap in the
> escape hatch and expensive in a classifier arm.** In the hatch it simply never matches, and
> `stderr_len`+`tok` still land. In an arm it actively mis-routes the operator. This is the
> direct generalization of learning §3's *"bare terms are cheap in a LATE arm and expensive in an
> EARLY one."* It is why the brief's three falsified tokens are **safe to probe in `kw`** and
> **unsafe to promote to arms** — and `kw` is exactly how we find out which of them was right.

**Sharp edge — `tail -c 400` truncates the HEAD.** The existing capture is
`zdetail="$(tail -c 400 "$zerr")"`. The measured daemon-down stderr is 346 bytes and multi-line;
anything longer means the "first token" of the tail is **mid-message garbage**. `tok` MUST be
read from `head -c` on the file, not from the tail-truncated string. `stderr_len` MUST be the
**true** length (`wc -c < "$zerr"`), not the truncated one — otherwise it saturates at 400 and
silently stops being a measurement.

`$zerr` stays `0600` and is `rm -f`'d on **both** branches (unchanged).

### Phase 3 — GHCR parity: capture + classify, reusing the existing classifier

Both GHCR sites currently discard stderr:

- `ci-deploy.sh:803` — the prelude login.
- `ci-deploy.sh:746` — inside `refetch_ghcr_and_relogin`.

Capture to a `0600` temp exactly as the zot site does and classify with the **same**
`_zot_login_failure_class`. **Do not fork a second classifier.** Rename it to a registry-neutral
`_docker_login_failure_class` (it is no longer zot-specific), keeping `_zot_login_http_status`'s
`status:` anchor logic likewise. Emit the class on both PRELUDE log lines and on the Sentry
event.

### Phase 4 — the `cred_store` arm, gated on measurement, ordered before `transport`

Add **one** arm, `cred_store`, anchored **only** on measured literals:
`error saving credentials|error storing credentials|error getting credentials`.

**It MUST precede `transport`.** Measured: the EACCES variant is
`error saving credentials: open <path>: permission denied` — `transport`'s bare `permission
denied` matches it. Without the reorder the new arm is dead for that variant.

This makes ordering load-bearing again, which learning §3 flags as *"a red flag, not a
defense"* — correctly. Meeting that objection head-on rather than ignoring it:

- The overlap is **real and measured**, not hypothetical. `permission denied` genuinely appears
  in two different subsystems' errors.
- The resolution is the one the file already uses and documents for `authn_rejected` (kept first
  because the GHCR shape `denied: authentication required` renders a 401 containing "denied").
  This is the *same* precedent, applied for the *same* reason.
- It is **pinned by a test**, not by a comment: feed the measured EACCES string, assert
  `cred_store`. That test fails if anyone reorders the arms.

`cred_store` is deliberately **distinct from `transport`**: a socket/daemon/config failure is not
a network failure, and conflating them sends the operator to the wrong subsystem — the exact
mistake the 2026-07-15 review caught.

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
| `apps/web-platform/infra/ci-deploy.sh` | Phases 1-5. Rename classifier registry-neutral; `cred_store` arm before `transport`; capture+classify both GHCR sites; `stderr_len`/`kw`/`tok` escape hatch at both sites; comment truth-up. |
| `apps/web-platform/infra/ci-deploy.test.sh` | New cases + `assert_ghcr_login_class` + `MOCK_GHCR_LOGIN_FAIL_STDERR` mock arm; mutation battery. |
| `apps/web-platform/infra/zot-registry.tf` | **Comment-only.** Two falsified causal claims (`:108-109`, `:332`). |
| `knowledge-base/project/learnings/2026-07-15-false-comment-…-restated-it.md` | 3-line dated addendum: root cause falsified; lesson stands. |
| `knowledge-base/project/specs/feat-one-shot-6497-login-gate-unclassified/decision-challenges.md` | The successor-issue User-Challenge (headless path). |

**Files NOT to edit:** `cloud-init-registry.yml`, `zot-disk-heartbeat.sh`, ADR-115 — the
htpasswd edge and its probe are correct and converged; only their *causal attribution* is wrong,
and that lives in comments.

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
  what: ZOT_GATE / PRELUDE journald lines + WEB-PLATFORM-5B Sentry beacon, now carrying
        login_class + stderr_len + kw + tok for EVERY failed login on BOTH registries
  cadence: every deploy (~6-12/day observed)
  alert_target: Sentry WEB-PLATFORM-5B (existing issue), Better Stack source soleur-inngest-vector-prd
  configured_in: apps/web-platform/infra/ci-deploy.sh (zot_gate_degraded_event)
error_reporting:
  destination: Sentry store endpoint (existing transport, fail-open curl)
  fail_loud: false — fail-open by design; a telemetry failure must never abort a deploy
             (set -euo pipefail; see Risks R1)
failure_modes:
  - mode: GHCR login fails, cause unknown
    detection: PRELUDE line now carries class= + stderr_len= (was: silently discarded)
    alert_route: Sentry WEB-PLATFORM-5B
  - mode: zot login fails with a stderr matching no arm
    detection: class=unclassified + stderr_len>0 + kw/tok naming the shape
    alert_route: Sentry WEB-PLATFORM-5B
  - mode: zot login fails with NO stderr at all
    detection: class=unclassified + stderr_len=0 — the empty/unmatched split (Phase 1)
    alert_route: Sentry WEB-PLATFORM-5B
  - mode: credential-store failure misrouted to the network subsystem
    detection: cred_store arm ordered before transport; pinned by the measured-EACCES test
    alert_route: Sentry WEB-PLATFORM-5B (tag zot_login_class=cred_store)
logs:
  where: journald on web-1 (SYSLOG_IDENTIFIER=ci-deploy) → Vector → Better Stack
  retention: Better Stack remote() ~40-min hot window; archive arm required for any
             soak-length span
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    --since 60 --grep ZOT_GATE
  expected_output: >
    a ZOT_GATE line carrying class=<enum> and, when class=unclassified,
    a non-empty stderr_len= field. NO ssh.
```

**The registry host is deny-all/no-SSH.** Every step here is Better Stack + Sentry + `gh`.
No step asks the operator to fetch, paste, or eyeball anything
(`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-no-ssh-fallback-in-runbooks`).

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — measurement is re-run on the pinned host docker version**, and every arm in the diff
  cites a string measured there. Any divergence from this plan's table amends the plan.
  *(Falsifier: an arm whose literal appears in no measured output.)*
- **AC2 — `set -euo pipefail` survival, verified BEHAVIOURALLY on `ubuntu:24.04`**, not by
  inspection: run the gate inside `docker run --rm ubuntu:24.04` with **each** new variable unset
  in turn; the telemetry line must still render and the script must not abort. Every new
  expansion is `${x:-}`-guarded **at the expansion site** — a `||` fallback does **not** rescue an
  expansion error under `set -u` (learning §1). *(Falsifier: any unset var that aborts the run.)*
- **AC3 — the escape hatch cannot echo its input.** Feed a stderr containing a synthetic
  credential-shaped token and a username; assert the rendered Sentry payload contains **neither**,
  and that every emitted `kw`/`tok` value is a member of the closed allow-list. *(Falsifier: any
  input byte reaching the payload.)*
- **AC4 — `stderr_len` splits the bucket.** Two cases: empty stderr → `class=unclassified
  stderr_len=0`; unmatched non-empty stderr → `class=unclassified stderr_len=<true length>`.
  Assert the two payloads **differ**. *(Falsifier: identical payloads — today's behaviour.)*
- **AC5 — `stderr_len` is the TRUE length, not the truncated one.** Feed a >400-byte stderr;
  assert `stderr_len` > 400. *(Falsifier: saturation at 400.)*
- **AC6 — `cred_store` precedes `transport`, pinned by the measured string.** Feed
  `error saving credentials: open /home/deploy/.docker/config.json123: permission denied`;
  assert `cred_store`, **not** `transport`. *(Falsifier: reordering the arms → RED.)*
- **AC7 — GHCR parity.** `git grep -c '>/dev/null 2>&1' apps/web-platform/infra/ci-deploy.sh`
  returns **0 matches on any `docker login` line**. Verify with a login-line-scoped grep, not a
  file-wide count (other commands legitimately discard output):
  `git grep -n 'docker login' apps/web-platform/infra/ci-deploy.sh | grep -c '2>&1'` → `0`.
- **AC8 — the GHCR class rides the PRELUDE lines and the Sentry event**, asserted via a new
  `assert_ghcr_login_class` mirroring `assert_zot_login_class` (`:3458`).
- **AC9 — mutation battery, each proven RED before green** (learning §5: *mutate a sibling
  attribute IN, not just the anchor OUT*; **relocation**, not deletion):
  - Move `cred_store` **after** `transport` → AC6 RED.
  - Replace `stderr_len` with the `tail -c 400` length → AC5 RED.
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
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 90 --grep ZOT_GATE
  ```
  **must** yield a login outcome carrying a **bounded, non-empty** shape — i.e. either a class
  other than `unclassified`, **or** `unclassified` **with** `stderr_len` + `kw`/`tok` populated.

  > **Deliberately NOT `class == cred_store`.** That would assert a *proxy for a hypothesis*
  > rather than *the invariant this PR delivers*. The PR's contract is **"the gate can name its
  > failure"**, and that must hold whether the cause is H-A, H-B, H-C, H-D, **or the login stops
  > failing entirely** (also a valid, observable outcome). An AC pinned to a specific cause would
  > go red on correct code — the plan-skill's vacuous/unsatisfiable-assert trap.

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
| **R1** | A new variable is expanded bare under `set -euo pipefail` → aborts the deploy, or takes the telemetry line dark. **This was the 2026-07-15 review's #1 P1.** | `${x:-}` at **every** expansion site as a **precondition**, never a downstream correction (`||` cannot catch an expansion error). AC2 verifies **behaviourally on ubuntu:24.04**, unset-var by unset-var. |
| **R2** | The escape hatch becomes a passthrough and ships a credential/username to Sentry. | Fixed-vocabulary emitter: `kw` probes are `grep -q` → hardcoded literal; `tok` is a closed allow-list with `other` as default. AC3 + the mutation that swaps in a raw passthrough → RED. |
| **R3** | The `cred_store` arm is built on an unmeasured string and never fires — decoration, and CI can never fail on an arm that never fires (learning §2/§3). | Arms cite only measured literals. The three falsified tokens are demoted to `kw` probes, where being wrong costs nothing. AC1 re-measures on the pinned version. |
| **R4** | Reordering arms silently regresses `transport`'s live coverage — it is the arm that fires most on this fleet (#6415 private-NIC → `network is unreachable`; zot OOM → `connection reset`). | `cred_store`'s literals are `error {saving,storing,getting} credentials` — disjoint from every transport shape **except** via `permission denied`, which is exactly the overlap the reorder exists to resolve. The existing T-5B-5b..5f transport cases must stay green (AC12). |
| **R5** | The bug is transient and the next deploy shows no failure → AC13 unverifiable. | AC13 asserts the **invariant** (the gate names its outcome), not a **cause**. Green under every hypothesis including recovery. |
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
