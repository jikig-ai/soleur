---
issue: 5960
type: fix
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
adr: ADR-079 (amend — item 4 redeploy/loaded-hash contract)
created: 2026-07-03
plan_review: 5-agent panel applied (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) — see "Plan-Review Reconciliation"
branch: feat-one-shot-5960-seccomp-loaded-sha
---

# fix(infra): apply-deploy-pipeline-fix.yml — seccomp redeploy poll latches a foreign/lock-contention terminal; deploy-status can't prove the loaded profile

Ops-remediation fix: the assert can only be proven green by a real
`apply-deploy-pipeline-fix.yml` run, so use `Ref #5960` in the PR body, not
`Closes #5960` — the workflow's own green run + `gh issue close` is the closure
(ops-remediation Sharp Edge; `Closes` would false-close at merge before the run
proves green).

## Overview

`.github/workflows/apply-deploy-pipeline-fix.yml`'s **"Redeploy to load applied
profile and assert loaded==committed (#5875 item 4)"** step fails with
`LOADED != COMMITTED` because `/hooks/deploy-status`'s `seccomp_profile_sha256`
came back **empty**. After #5955/#5957 cleared the `tag_malformed` wedge, this
third latent defect in the never-green #5875 item-4 mechanism surfaced.

Two things are broken; the fix does both plus the discriminating probe the issue's
"Next step" asks for:

1. **The redeploy poll latches a terminal that is NOT the redeploy's swap**
   (behavioral root cause). The run log shows the poll declared terminal after
   **~31 s** — physically impossible for a real canary swap — so
   `write_seccomp_profile_hash` (the only seccomp-hash write site) never ran for
   the observed state. The poll accepts any `exit_code>=0` frame and does not
   check `component`/`tag`/`reason`, so it latches stale, foreign-component, or —
   as the review panel proved — **`lock_contention`** terminals (which the flock
   loser stamps with *our* `component=web-platform` + *our* `tag`). Fix: accept
   only a genuine web-platform swap terminal of the target tag; treat
   `lock_contention`/`adr027_prod_already_running`/`running` as **non-terminal**
   (keep polling — the flock winner loads the same profile).
2. **`/hooks/deploy-status` exposes only the ephemeral recorded hash, never the
   live loaded profile** (the affected-surface observability gap the issue names).
   Add a live `docker inspect HostConfig.SecurityOpt` read of the running
   container's actual loaded profile + a live host-file discriminator, reusing the
   proven `audit-bwrap-uid.sh:105-146` technique. This lets the assert distinguish
   *not-delivered* / *host-stale* / *not-reloaded* in **one** deploy-status read,
   no SSH.
3. **Assert a skew-immune, self-diagnosing STATE invariant.** #5875 item-4's real
   contract is "the running container is enforcing the committed profile."
   Decompose it into two comparisons that never cross jq versions:
   `host_sha256(raw) == committed(raw sha256sum)` (**delivery** — byte-identical
   file copy, `sha256sum` is version-independent) **AND**
   `loaded == host` computed **host-side with one jq** (**reload** — skew-immune
   by construction). No cross-machine `jq -cS` comparison anywhere; the committed
   side stays raw `sha256sum` (unchanged from today).

Detail level: **A LOT** (multi-file infra + workflow + ADR amendment + tests; a
security-boundary verification gate at `aggregate pattern` threshold).

## Plan-Review Reconciliation (5-agent panel)

The v1 plan was reviewed by DHH, Kieran, code-simplicity, architecture-strategist,
and spec-flow. Material changes folded into this v2:

- **[BLOCKING — spec-flow + architecture-strategist]** `lock_contention` losers
  write `component=web-platform, tag=$TARGET_TAG, exit_code=1` with a fresh
  `start_ts` (`ci-deploy.sh:207` sets `START_TS` before flock; `:674` parses
  COMPONENT/TAG before the flock at `:742`). v1's tightened predicate would
  **match and fail-loud** on our own lock loss under a concurrent
  web-platform-release deploy. **Fix:** treat `lock_contention` /
  `adr027_prod_already_running` / `running` as non-terminal → keep polling.
- **[DHH + Kieran + architecture-strategist consensus]** Make the load-bearing
  equality `loaded == host` (both computed with the **host** jq, skew-immune) and
  the delivery check raw `sha256sum(host) == sha256sum(committed)` (version-
  independent). This **eliminates the cross-jq `jq -cS` comparison** that v1 put on
  the load-bearing path — and with it SE-B1 (jq-version parity) and the
  canonicalization ACs entirely. Committed side stays **raw** (`:487` unchanged).
- **[DHH + code-simplicity consensus]** Trim scope: **drop** `seccomp_profile_host_path`
  (a self-referential constant the script can't cross-check against the other
  files that actually drift) and **drop** `seccomp_recorded_loaded_at` (telemetry
  on a field being demoted). **Collapse the Phase-4 deprecate-then-remove ceremony**:
  leave `write_seccomp_profile_hash` in place permanently as an inert raw
  diagnostic (already `|| true`, never gates); the workflow simply stops asserting
  it. No tracking issue, no soak-gated removal PR.
- **[architecture-strategist]** Freeze the terminal snapshot (`cp
  /tmp/redeploy-status.json /tmp/redeploy-terminal.json`) so the load-bearing read
  and all discriminator reads share ONE frame (`get_status()` overwrites the file
  each call).
- **[Kieran]** Add an AC forbidding any leftover `.seccomp_profile_sha256` read on
  the load-bearing/fast-path (guards the partial-migration false-red). Fix Phase 6
  wording: the docker mock must be **ported** from `audit-bwrap-uid.test.sh:26`
  (`create_docker_mock` PATH shim) — `cat-deploy-state.test.sh` currently mocks
  nothing.
- **[spec-flow Q2 + Q3]** Baseline fast-path: settle + re-read once on a
  transient-empty loaded read before triggering a 70-min redeploy. **STATE-invariant
  reframe** (see below) closes the concurrent-starvation false-red WITHOUT a deploy
  nonce — nonce **considered and rejected** as over-build (the assert verifies a
  STATE, "the committed profile is loaded now", not provenance, "our POST did it").

**STATE-invariant framing (resolves the concurrency findings without a nonce):**
the assert's true invariant is *"the running container is enforcing the committed
seccomp profile,"* a property of current host state — not *"our specific redeploy
caused it."* So a concurrent web-platform-release deploy that loads the **same**
committed profile satisfies the invariant. The poll therefore (a) treats
`lock_contention`/`running` as non-terminal, and (b) on poll-window exhaustion,
does ONE final state check: if `host_present && host_sha==committed(raw) &&
loaded==host` holds now, **PASS** (the profile is loaded regardless of which deploy
loaded it); else fail-loud UNVERIFIED. This is strictly cheaper and more correct
than threading a nonce through POST → `write_state` → deploy-status.

## Premise Validation (Phase 0.6)

- `#5955` **CLOSED**, `#5957` **MERGED** (tag resolution). `#5875` **CLOSED**,
  `#5950` **MERGED**. `ADR-079` present with amendments (#5913, #5955) — this adds
  a fourth (no new ordinal; collision risk = none).
- **Failing run 28661894954 log inspected** (smoking gun below). Code anchors
  confirmed by direct read: `ci-deploy.sh:207` `START_TS` (pre-flock), `:674`
  COMPONENT/TAG parse (pre-flock), `:742-745` `lock_contention`, `:1132-1152` prod
  `docker run`, `:1161` `write_seccomp_profile_hash` (sole call site), `:1211/1213`
  `final_write_state 0 "ok"/"ok_peer_fanout_degraded"`. Committed side is **raw**
  `sha256sum` (`apply-deploy-pipeline-fix.yml:487`); recorded write is **raw**
  (`ci-deploy.sh:488`) — so raw==raw today (both `7654ef34…`).
- **Own-capability claim verified** (`hr-verify-repo-capability-claim`): reading
  the loaded seccomp via `docker inspect` is **not novel** —
  `apps/web-platform/infra/audit-bwrap-uid.sh:105-146` already does it (Docker
  inlines the resolved `--security-opt seccomp=<path>` as JSON into
  `HostConfig.SecurityOpt`; hash-compares `jq -cS` canonical, with an EMPTY_HASH
  guard at `:137-140` and literal-path drift detection at `:123`). The fix reuses
  this pattern.

## Root Cause Analysis

### The smoking gun: a 31-second "terminal"

From run 28661894954 (`workflow_dispatch` on `main` after #5957):

```
12:55:25  Running container loaded seccomp sha256: '<none>' (tag='v0.184.6')
12:55:26  Redeploy initiated (HTTP 202). Polling for completion…
12:55:57  Redeploy terminal after 1 poll(s): exit_code=0 loaded= canary=unknown
12:55:57  ##[error]LOADED != COMMITTED after redeploy: loaded='' committed='7654ef34…'.
```

The poll (`apply-deploy-pipeline-fix.yml:574-589`) does `sleep 30` then checks. It
declared terminal on the **first** iteration — ~31 s. A real `ci-deploy.sh`
web-platform deploy **cannot** finish in 31 s (prune + pull + plugin-seed + canary
`docker run` + 10-iteration health probe loop + bwrap + faithful canary + ADR-078
cron drain + prod `docker run` = minutes). **There is no fast-path**: the only
web-platform `final_write_state 0` is `:1211/1213` after the full swap;
`write_seccomp_profile_hash` (`:1161`) runs immediately before it (verified: five
`final_write_state 0` sites total — `:771`/`:1416`/`:1419` are inngest/restart, not
web-platform). `canary=unknown` + `loaded=''` confirm the observed frame is **not**
a completed swap.

The poll's predicate is **only** `exit_code >= 0 && start_ts > PRIOR_START` (`:581`)
— no `component`/`tag`/`reason` guard — so it latches stale, foreign-component
(inngest/restart reach `final_write_state 0`), or **`lock_contention`** terminals.
The `lock_contention` case is the sharpest: because `START_TS` is set pre-flock
(`:207`) and COMPONENT/TAG are parsed pre-flock (`:674`), a flock loser under a
concurrent web-platform-release deploy writes `component=web-platform,
tag=$TARGET_TAG, exit_code=1, reason=lock_contention` with `start_ts>PRIOR_START`
— and that frame **persists for the winner's entire multi-minute swap** (the state
file is only re-written at terminals). This is the terminal-frame trap from
`2026-06-14-terminal-frame-to-terminal-ui-state-must-validate-reason-set-and-confirm-before-success.md`.

### The observability gap: recorded ≠ loaded

`seccomp_profile_sha256_value()` reads **only** the ephemeral
`/var/run/ci-deploy-seccomp-profile.json` (written by `write_seccomp_profile_hash`
on the swap path, reboot-cleared per #5877). It never reads the **live** host
profile nor the **running container's actually-loaded** profile, so an empty field
cannot discriminate the failure classes:

| Hypothesis | Old signal | New discriminator |
|---|---|---|
| Wrong/no-swap terminal latched | `seccomp_profile_sha256=''` | poll waits for a real swap; `loaded==host` read live |
| Provisioner never delivered | `seccomp_profile_sha256=''` | `seccomp_profile_host_present` |
| Host has stale/wrong profile | `seccomp_profile_sha256=''` | `seccomp_profile_host_sha256(raw) != committed` |
| Container didn't reload | `seccomp_profile_sha256=''` | `seccomp_profile_loaded_matches_host == false` |

Direct application of `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`
(ship the discriminating probe FROM the blind surface first).

## User-Brand Impact

**If this lands broken, the user experiences:** `apply-deploy-pipeline-fix.yml`
stays red; every future seccomp/apparmor-profile change auto-applies to the host
but the gate that proves the running container actually *loaded* the committed
profile cannot confirm — so a #5874-style agent-sandbox seccomp regression could
ship "applied but not loaded" and every tenant's Concierge Bash sandbox breaks
(EPERM on `unshare`) with no CI signal, exactly the outage #5875 item-4 exists to
prevent.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no
personal-data or credential surface is touched. The seccomp profile is a syscall
allow/deny boundary; the risk is *under-restriction* (a permissive profile loaded
and not caught), a security-posture regression, not a data leak.

**Brand-survival threshold:** `aggregate pattern` — carried forward from ADR-079
(CTO + architecture-strategist confirmed this fix does not alter it).
`threshold: aggregate pattern, reason: security-posture verification gate for the
shared agent-sandbox syscall boundary; no per-user data/credential surface.`

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (direct one-shot → plan path). The issue body's
three candidate root causes, tested against code + run log:

| Issue-body candidate | Reality (verified) | Plan response |
|---|---|---|
| (1) success branch skipped `write_seccomp_profile_hash` | No web-platform fast-path; `:1161` always precedes `:1211`. The **poll latched a non-swap / lock_contention terminal** (31 s) | Fix the poll (Phase 3); live `loaded==host` read (Phase 1) also makes the skip-path moot |
| (2) provisioner didn't deliver → file absent | `docker run --security-opt seccomp=<file>` succeeded ⇒ present | `seccomp_profile_host_present` proves it (Phase 1) |
| (3) write ran before file in place / path mismatch | write path (`:195`) == run path (`:1140`) == provisioner dest (server.tf) — all `/etc/docker/seccomp-profiles/soleur-bwrap.json` | `host_sha(raw)==committed` + `loaded==host` catch any drift (Phase 1/2) |

## Implementation Phases

> **Phase order is load-bearing** (contract-before-consumer): the producer
> (Phase 1) precedes the consumer (Phase 2/3). Both merge atomically; `/work`
> reads phases sequentially.

### Phase 1 — Add live loaded + host discriminators to `cat-deploy-state.sh`

File: `apps/web-platform/infra/cat-deploy-state.sh`. Add read-only helpers
mirroring the sibling `container_restart_json` (`docker inspect`), reusing the
`audit-bwrap-uid.sh:105-146` technique. **Three new fields (all skew-safe):**

- **`seccomp_profile_loaded_matches_host`** (bool) — the **reload** proof,
  computed host-side so it never crosses jq versions:
  1. `SECCOMP_ENTRY` from `docker inspect "${CONTAINER_NAME:-soleur-web-platform}"
     --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' 2>/dev/null
     || true`, then `sed -n 's/^seccomp=//p' | head -n1`.
  2. If the entry is inlined JSON (NOT a literal `/path` — `audit-bwrap-uid.sh:123`
     drift), compute `INLINED=printf '%s' "$SECCOMP_ENTRY" | jq -cS . | sha256sum`
     and `HOSTC=jq -cS . "$SECCOMP_PROFILE_HOST_PATH" | sha256sum`, both with the
     **same host jq**. `matches = (INLINED == HOSTC && INLINED not empty-hash)`.
  3. `false` on any failure (no docker, container down, literal-path, unparseable,
     empty-hash). Apply the `audit-bwrap-uid.sh:137-140` EMPTY_HASH guard so a `jq`
     failure never yields `sha256("")`.
- **`seccomp_profile_host_sha256`** (raw) — the **delivery** discriminator:
  `sha256sum "$SECCOMP_PROFILE_HOST_PATH" | cut -d' ' -f1` (RAW bytes, matches the
  workflow's raw `COMMITTED_SHA`; `""` if absent). `sha256sum` is version-
  independent, so `host==committed` is skew-free.
- **`seccomp_profile_host_present`** (bool) — `[[ -f "$SECCOMP_PROFILE_HOST_PATH" ]]`.
- `SECCOMP_PROFILE_HOST_PATH` default must match `ci-deploy.sh:195` exactly.
- **Keep** the existing `seccomp_profile_sha256` (raw recorded) field untouched as
  an inert diagnostic. **Do NOT** add `seccomp_recorded_loaded_at` or
  `seccomp_profile_host_path` (review: constant / dying-field telemetry).
- Extend the `jq` merge (`$base + $cr + $cd + { … }`) with the three new keys; do
  NOT clobber the load-bearing top-level `exit_code`.

**Why `loaded==host` not `loaded==committed`:** #5875 item-4 = "container enforcing
the committed profile" = `(host==committed)` AND `(loaded==host)`. Splitting keeps
each comparison within one hash space — raw `sha256sum` for the cross-machine
delivery leg, host-jq `jq -cS` for the same-machine reload leg — so no cross-jq
`jq -cS` comparison exists. Verified: the profile's largest ints (`4294967295`,
`2114060288`) are < 2⁵³ and the file is ASCII, so even the reload leg is jq-version-
robust today; the decomposition removes the hazard by construction regardless.

### Phase 2 — Robust, self-diagnosing, snapshot-bound assert

File: `.github/workflows/apply-deploy-pipeline-fix.yml` (the "Redeploy…" step,
`:486-613`).

- Keep `COMMITTED_SHA=$(sha256sum seccomp-bwrap.json | cut -d' ' -f1)` **raw**
  (`:487` unchanged). There is NO canonical committed hash.
- **Baseline / fast-path**: read `seccomp_profile_loaded_matches_host`,
  `seccomp_profile_host_present`, `seccomp_profile_host_sha256`. Skip the redeploy
  iff `host_present==true && host_sha256==COMMITTED_SHA && loaded_matches_host==true`
  (state already correct). If `loaded_matches_host==false` at baseline, **settle
  once** (short sleep) and re-read before deciding to redeploy — avoids a 70-min
  redeploy triggered by a transient in-flight swap window (spec-flow Q2).
- **Poll → freeze the terminal frame**: at terminal acceptance,
  `cp /tmp/redeploy-status.json /tmp/redeploy-terminal.json` and read BOTH the
  load-bearing fields AND all discriminators from that frozen frame (never a fresh
  post-loop GET — architecture-strategist #2).
- **Load-bearing assert** (from the frozen frame):
  `host_present==true && host_sha256==COMMITTED_SHA && loaded_matches_host==true`.
- **Fail-loud discriminator classes** (no leftover `.seccomp_profile_sha256` read
  on this or the fast path — Kieran #1):
  - `host_present==false` → "provisioner did not deliver profile to
    `/etc/docker/seccomp-profiles/soleur-bwrap.json`".
  - `host_sha256 != COMMITTED_SHA` → "host has a STALE/wrong profile
    (`<host_sha>` != committed) — delivery/path drift".
  - `loaded_matches_host==false` (host_sha ok) → "profile on host but running
    container did NOT reload it".
- **Timeout graceful-degradation** (STATE invariant): if the poll window exhausts
  without an accepted swap terminal (e.g. a concurrent release starved our tag via
  `lock_contention`), do ONE final `get_status` + freeze + state check — if
  `host_present && host_sha256==COMMITTED_SHA && loaded_matches_host` holds now,
  **PASS**; else fail-loud UNVERIFIED. No deploy nonce (considered, rejected).
- Keep the existing `sandbox_canary.verdict == sandbox_broken` fatal branch and the
  poll ceiling (160×30 s) unchanged.

### Phase 3 — Fix the redeploy poll: accept only the genuine swap terminal; lock_contention is non-terminal

File: `.github/workflows/apply-deploy-pipeline-fix.yml` (poll loop `:574-604`).

- Read `component`, `tag`, `reason`, `exit_code`, `start_ts` from the status frame
  (all emitted by `write_state`, `ci-deploy.sh:228` — no new plumbing).
- **Terminal acceptance** requires `component=="web-platform" && tag=="$TARGET_TAG"
  && exit_code>=0 && start_ts>PRIOR_START`.
- **Adjudication** (this is the BLOCKING fix):
  - `reason ∈ {ok, ok_peer_fanout_degraded}` (both permanently allowlisted; SE-C1)
    → accept → run the Phase 2 assert.
  - `reason ∈ {lock_contention, adr027_prod_already_running}` OR `exit_code==-1`
    (`running`, `EXIT_RUNNING=-1`) → **NON-TERMINAL, keep polling** (the flock
    winner produces the authoritative terminal loading the same committed profile).
  - any other `component=web-platform && tag=$TARGET_TAG` terminal with a genuine
    failure reason (`canary_health_failed`, `production_start_failed`, `timeout`,
    `unhandled`, …) / `exit_code!=0` → **fail loud** with that reason.
  - foreign `component` / mismatched `tag` / `start_ts<=PRIOR_START` → ignore
    (keep polling).
- On poll exhaustion → the Phase 2 timeout graceful-degradation state check.
- Do NOT widen the poll wall-clock.

### Phase 4 — Stop asserting the recorded field (no removal)

- The workflow no longer reads `.seccomp_profile_sha256` on any load-bearing or
  fast path (Phase 2/3 use the new fields). **Leave** `write_seccomp_profile_hash`
  (`ci-deploy.sh:479/1161`) and the emitted `seccomp_profile_sha256` field in place
  **permanently** as an inert raw diagnostic (already `|| true`, never gates,
  mirrors `write_sandbox_canary_state`). No deprecation cycle, tracking issue, or
  removal PR (review: the removal ceremony costs more than the ~15-line inert
  helper it would delete).

### Phase 5 — ADR-079 amendment

File: `knowledge-base/engineering/architecture/decisions/ADR-079-…​.md`. Add
**`### Amendment (#5960, 2026-07-03) — loaded proof read live from the running
container; poll validates the swap terminal and treats lock_contention as
non-terminal`** after the #5955 amendment. Terse (4-6 lines per architecture-
strategist + code-simplicity): old contract (ephemeral recorded hash + latch-any-
terminal poll) → new contract (`loaded==host` live via `docker inspect`, host-jq;
`host==committed` raw `sha256sum`; poll requires `component=web-platform &&
tag=TARGET_TAG` and keeps polling on `lock_contention`/`running`; STATE-invariant
timeout fallback). Note the marginal second `docker inspect` per
`/hooks/deploy-status` GET (same pattern as `container_restart_json`). No new
`TF_VAR_*`, no topology change, `aggregate pattern` unchanged, amendment not a new
ordinal.

### Phase 6 — Tests

File: `apps/web-platform/infra/cat-deploy-state.test.sh` (extend; `.test.sh`
bash-with-mocks — **do NOT introduce bats**).

- **PORT** the `create_docker_mock` PATH shim from `audit-bwrap-uid.test.sh:26`
  (cat-deploy-state.test.sh currently mocks nothing — Kieran #3). Reuse
  `test-fixtures/audit-bwrap/inspect-pass.txt`, `inspect-literal-path.txt`,
  `valid-seccomp.json`.
- New cases (mock `docker inspect`; env-override `SECCOMP_PROFILE_HOST_PATH` at a
  tmp fixture):
  1. Loaded == host (inlined JSON canonical-equals host file) →
     `seccomp_profile_loaded_matches_host==true`, `seccomp_profile_host_sha256`
     = raw sha of the fixture, `seccomp_profile_host_present==true`.
  2. Loaded != host (drift fixture) → `matches==false`.
  3. Literal-path seccomp entry → `matches==false`.
  4. Container down / docker absent → `matches==false`, host fields still populated.
  5. Host file absent → `host_present==false`, `host_sha256==""`, `matches==false`.
  6. Merge integrity: new fields present AND top-level `exit_code` unchanged.
  7. Empty-hash guard: a mocked `jq` failure yields `matches==false`, never a
     `sha256("")` true-match.

## Files to Edit

- `.github/workflows/apply-deploy-pipeline-fix.yml` — Phase 2 (raw delivery +
  `loaded==host` assert + frozen snapshot + discriminator diagnosis + timeout
  state check), Phase 3 (poll predicate + lock_contention non-terminal), Phase 4
  (stop reading recorded field). **In its own `paths:` trigger — re-fires on merge.**
- `apps/web-platform/infra/cat-deploy-state.sh` — Phase 1 (3 discriminator fields).
  Delivered by `terraform_data.deploy_pipeline_fix` FILE_MAP (`CAT_DEPLOY_STATE_SH_B64
  → /usr/local/bin/cat-deploy-state.sh`); in the workflow `paths:` filter (`:69`)
  → **auto-applies on merge**.
- `knowledge-base/engineering/architecture/decisions/ADR-079-…​.md` — Phase 5.
- `apps/web-platform/infra/cat-deploy-state.test.sh` — Phase 6.

## Files to Create

- None. (ADR amended; tests extend an existing suite; fixtures reused.)

## Open Code-Review Overlap

None. Checked open `code-review`-labelled issues touching
`apply-deploy-pipeline-fix.yml`, `cat-deploy-state.sh`, `ci-deploy.sh`, ADR-079 —
no overlap. (Recorded so the next planner sees the check ran.)

## Observability

```yaml
liveness_signal:
  what: apply-deploy-pipeline-fix.yml "Redeploy … assert" step green;
        /hooks/deploy-status exposes seccomp_profile_loaded_matches_host==true,
        seccomp_profile_host_sha256==committed(raw), seccomp_profile_host_present==true
  cadence: on every merge to main touching a #5875/#5505 trigger file, and on
           manual workflow_dispatch
  alert_target: GitHub Actions run status (red step) + the ::error:: discriminator
                line in the run log
  configured_in: .github/workflows/apply-deploy-pipeline-fix.yml
error_reporting:
  destination: GitHub Actions ::error:: annotations naming the discriminator class
               (not-delivered / host-stale / not-reloaded / unverified);
               ci-deploy.sh already mirrors sandbox_canary FAIL to Sentry (unchanged)
  fail_loud: true
failure_modes:
  - mode: poll latches a foreign / lock_contention / stale terminal
    detection: terminal accepted only when component=web-platform && tag=TARGET_TAG
               && exit_code>=0 && start_ts>PRIOR_START; lock_contention/running →
               keep polling; genuine failure reason → fail loud
    alert_route: red step + ::error:: with the observed reason
  - mode: provisioner did not deliver profile to host
    detection: seccomp_profile_host_present==false
    alert_route: red step + "provisioner did not deliver profile"
  - mode: host has a stale/wrong profile (delivery/path drift)
    detection: seccomp_profile_host_sha256(raw) != committed(raw sha256sum)
    alert_route: red step + "host has STALE profile"
  - mode: profile on host but running container did not reload it
    detection: seccomp_profile_loaded_matches_host==false while host_sha==committed
    alert_route: red step + "container did NOT reload"
logs:
  where: GitHub Actions run log; ci-deploy.sh journald (LOG_TAG) surfaced via
         /hooks/deploy-status journal tails
  retention: GitHub Actions default (90d); journald persistent (#4792)
discoverability_test:
  command: >
    curl -s -H "X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac
    "$WEBHOOK_SECRET" | sed 's/.*= //')" -H "CF-Access-Client-Id: $CF_ACCESS_ID"
    -H "CF-Access-Client-Secret: $CF_ACCESS_SECRET"
    https://deploy.soleur.ai/hooks/deploy-status | jq
    '{matches: .seccomp_profile_loaded_matches_host,
      host_present: .seccomp_profile_host_present, host_sha: .seccomp_profile_host_sha256}'
  expected_output: >
    matches==true; host_present==true; host_sha == sha256sum(committed
    seccomp-bwrap.json)  (NO ssh)
```

### Affected-surface observability (Phase 2.9.2)

The prod host + `/hooks/deploy-status` are a **blind execution surface** (no SSH —
`hr-no-ssh-fallback-in-runbooks`). Every `failure_modes` `detection` is an
**in-surface** probe read live FROM the host (`docker inspect` of the running
container; `sha256sum`/`jq -cS` of the host file), and the structured fields
(`seccomp_profile_loaded_matches_host`, `seccomp_profile_host_present`,
`seccomp_profile_host_sha256`) **discriminate all competing root-cause hypotheses
in a single deploy-status read**. Direct application of
`2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-079** (item-4 redeploy/loaded contract) — Phase 5. Within-scope
verification-mechanism correction (how "loaded" is read; how the poll validates the
terminal), not a binding-ruling reversal → amendment, not a new ADR (precedent:
#5913, #5955 amend the same item-4 mechanism). CTO + architecture-strategist concur.

### C4 views

**No C4 impact.** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none added (the CI runner is not a modeled person).
- **External systems / vendors:** none added; the CI↔prod-host deploy edge is
  already `engine -> github "Git operations and CI"` (`model.c4:255`).
- **Containers / data stores:** none added/falsified; the deploy webhook +
  `cat-deploy-state.sh` live inside the existing `hetzner` container
  (`model.c4:164`), below C4-container granularity.
- **Access relationships:** none change; the seccomp boundary is verified, not
  introduced or re-scoped.

No `.c4` element description is falsified; no `view include` edit required.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Small–medium infra/observability change (shell + workflow + ADR;
no DB/product/paging). CTO confirmed the three precedents and ruled: live
`docker inspect` read is architecturally sounder than the ephemeral state file
(ground-truth, reboot-durable, precedent-parity with `audit-bwrap-uid.sh`); name
the live signal distinctly (avoid overloading `seccomp_profile_sha256`);
canonicalization must be consistent AND, per the subsequent 5-agent panel, is best
avoided on the load-bearing path (raw delivery + host-jq reload); keep BOTH `ok`
and `ok_peer_fanout_degraded`; negative-scope (no `seccomp-bwrap.json` byte change,
no Sentry/paging change); amend ADR-079. Threshold stays `aggregate pattern`. All
SE items encoded as ACs / Sharp Edges below.

### Product/UX Gate

Not applicable. Mechanical UI-surface override did not fire: `## Files to Edit` is
`.yml`/`.sh`/`.md` only — no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`.
Tier: **NONE**.

## Infrastructure (IaC) / Apply-path

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

No **new** infrastructure. Both host-resident files are delivered by **existing**
IaC and auto-apply on merge — no operator SSH, no Doppler secret mutation, no
dashboard step:

- `cat-deploy-state.sh` → `terraform_data.deploy_pipeline_fix` FILE_MAP
  (`CAT_DEPLOY_STATE_SH_B64 → /usr/local/bin/cat-deploy-state.sh`), pushed via the
  HTTPS `/hooks/infra-config` webhook path. Already in the workflow `paths:` filter
  → the merge fires the apply.
- `apply-deploy-pipeline-fix.yml` is itself a workflow; the merge updates CI directly.
- Apply→verify sequence unchanged; no `terraform apply -replace`, no taint.

(Phase 2.8 gate reviewed: pure edits to an already-provisioned, IaC-delivered
surface — no `.tf` change. Ack comment above.)

## GDPR / Compliance

No regulated-data surface (no schema, migration, auth, API route, `.sql`, PII).
None of the (a)-(d) expansion triggers fire. **Gate skipped.**

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (reload proof, host-side & skew-immune).** `cat-deploy-state.sh` emits
  `seccomp_profile_loaded_matches_host` computed host-side (`jq -cS` docker-inlined
  == `jq -cS` host file, same jq), guarded with `|| true`/`2>/dev/null` and the
  EMPTY_HASH guard. Unit cases 1-4/7 cover equal/drift/literal-path/container-down/
  empty-hash.
- [ ] **AC2 (delivery proof, raw & skew-free).** `cat-deploy-state.sh` emits
  `seccomp_profile_host_sha256` as **raw** `sha256sum` (matches the workflow's raw
  `COMMITTED_SHA`), and `seccomp_profile_host_present` (bool). The workflow asserts
  `host_sha256 == COMMITTED_SHA` with `COMMITTED_SHA` staying raw (`:487`
  unchanged). No cross-jq `jq -cS` comparison exists anywhere in the assert.
- [ ] **AC3 (poll: lock_contention non-terminal — BLOCKING).** The poll accepts a
  terminal only when `component=="web-platform" && tag=="$TARGET_TAG" &&
  exit_code>=0 && start_ts>PRIOR_START`; `reason ∈ {lock_contention,
  adr027_prod_already_running}` and `exit_code==-1` (`running`) → **keep polling**;
  `reason ∈ {ok, ok_peer_fanout_degraded}` → assert; any other genuine-failure
  reason → fail loud. Verify the poll references `.component`, `.tag`, `.reason`;
  baseline-0: `git show origin/main:.github/workflows/apply-deploy-pipeline-fix.yml
  | grep -c '\.component'` == 0.
- [ ] **AC4 (no-fast-path finding).** `grep -n 'final_write_state 0'
  apps/web-platform/infra/ci-deploy.sh` (5 hits); PR notes `:1211/1213` are the
  only web-platform arm, so the tightened poll cannot false-timeout a legitimate
  swap.
- [ ] **AC5 (frozen snapshot).** On terminal detection the workflow `cp`s the
  status frame to a stable path and reads BOTH the load-bearing fields and all
  discriminators from that frozen frame (no post-loop fresh GET for the assert).
- [ ] **AC6 (no leftover recorded read — partial-migration guard).** No
  `.seccomp_profile_sha256` read remains on any load-bearing or fast-path
  comparison: `grep -n 'seccomp_profile_sha256' .github/workflows/apply-deploy-pipeline-fix.yml`
  shows the field only in diagnostic/echo context, never in an equality gate.
- [ ] **AC7 (self-diagnosing assert).** On mismatch the `::error::` names the
  class (not-delivered / host-stale / not-reloaded) from `host_present` /
  `host_sha256` / `loaded_matches_host`.
- [ ] **AC8 (timeout STATE check).** On poll exhaustion the workflow does one final
  state check and PASSES iff `host_present && host_sha256==COMMITTED_SHA &&
  loaded_matches_host`, else fails loud UNVERIFIED (no nonce).
- [ ] **AC9 (fast-path settle).** A transient-empty `loaded_matches_host` at
  baseline triggers a single settle+re-read before deciding to redeploy.
- [ ] **AC10 (no top-level clobber).** `exit_code` remains the DEPLOY sentinel;
  new fields do not overwrite it (merge-integrity test, case 6).
- [ ] **AC11 (negative scope).** The diff does NOT modify `seccomp-bwrap.json`
  bytes (`git diff --stat origin/main -- apps/web-platform/infra/seccomp-bwrap.json`
  empty) and does NOT touch `apps/web-platform/infra/sentry/` (dir exists — check
  is meaningful).
- [ ] **AC12 (tests green, mock ported).** `cat-deploy-state.test.sh` passes with
  the `create_docker_mock` PATH shim **ported** from `audit-bwrap-uid.test.sh:26`
  (not "reused" — the suite currently mocks nothing).
- [ ] **AC13 (ADR amended).** ADR-079 has a `### Amendment (#5960, 2026-07-03)`
  section; `grep -c '^# ADR-' <file>` stays 1.

### Post-merge (operator / automated)

- [ ] **AC14 (real green run — the only proof of "loaded").** After merge (or a
  `workflow_dispatch`), the redeploy step passes on a REAL swap:
  `loaded_matches_host==true && host_sha==committed`. Automation: `gh run
  watch`/`gh run view` — no SSH. Automatable via `/soleur:ship` post-merge verify +
  `gh workflow run`. This workflow has never run green (blocked by #5877 → #5955 →
  this); the first green must be on a real swap, not the STATE-fallback no-op.
- [ ] **AC15 (issue closure).** After AC14 green, `gh issue close 5960 --reason
  completed`. (`Ref #5960` in the PR body, NOT `Closes`.)

## Test Scenarios

1. **Foreign-terminal:** completed `inngest` deploy (`component=inngest,
   exit_code=0`, `start_ts>PRIOR_START`) → not accepted (component≠web-platform).
2. **lock_contention (the review-caught bug):** `component=web-platform,
   tag=v0.184.6, reason=lock_contention, exit_code=1, start_ts>PRIOR_START` →
   **keep polling** (NOT fail-loud). Must appear as an explicit scenario.
3. **Genuine swap terminal:** `component=web-platform, tag=v0.184.6, reason=ok` →
   accepted → assert.
4. **Genuine failure:** `component=web-platform, tag=v0.184.6,
   reason=canary_health_failed, exit_code=1` → fail-loud with reason.
5. **Concurrent starvation:** poll exhausts (release held the lock); final STATE
   check passes because the winner loaded the same committed profile.
6. **cat-deploy-state discriminators:** the 7 unit cases in Phase 6.

## Sharp Edges

- User-Brand Impact is filled (`aggregate pattern`) — clears deepen-plan 4.6.
- **`lock_contention`/`running` are NON-TERMINAL.** The flock loser stamps *our*
  `component`+`tag` with `exit_code=1` (`START_TS` pre-flock `:207`, parse pre-flock
  `:674`), and that frame persists for the winner's whole swap. Failing on it is a
  false-red under any concurrent web-platform deploy. Keep polling; the winner's
  `ok` is authoritative (or the timeout STATE check passes).
- **No cross-jq comparison on the load-bearing path.** Delivery = raw `sha256sum`
  (`host==committed`, version-independent); reload = host-jq `jq -cS`
  (`loaded==host`, same binary). Never compare a canonical loaded hash to the raw
  committed hash (raw `7654ef34…` ≠ canonical `36e758eb…`) — that's why the gate is
  `loaded==host`, not `loaded==committed`.
- **Empty-hash false-match.** A `jq` failure must yield `matches=false`, never
  `sha256("")`. Mirror `audit-bwrap-uid.sh:137-140`.
- **Snapshot must be frozen.** `get_status()` overwrites `/tmp/redeploy-status.json`
  each call — `cp` the terminal frame and read every field from the copy, or a
  concurrent in-flight swap yields a misleading discriminator class.
- **STATE not provenance (no nonce).** The assert verifies "the committed profile
  is loaded now," not "our POST loaded it." A concurrent release loading the same
  profile satisfies it; the timeout STATE check is the graceful path. A deploy
  nonce was considered and rejected as over-build.
- **`docker inspect … SecurityOpt` can return a literal path** (Docker didn't
  resolve `--security-opt seccomp=<path>`). Treat as `matches=false`
  (`audit-bwrap-uid.sh:123`), not a bogus hash.
- **The recorded `/var/run/…` file is tmpfs** (reboot-cleared). It stays a
  permanent inert diagnostic; never re-promote it to the gate.
- **Do NOT prescribe `bats`.** Extend `cat-deploy-state.test.sh`; **PORT**
  `create_docker_mock` from `audit-bwrap-uid.test.sh:26` (the suite mocks nothing
  today).
- **Do NOT prefix prose comments with `# shellcheck`** (`2026-06-02-shellcheck-comment-directives`).
- **Do NOT use `awk '/A/,/B/'` ranges in ACs** (self-match papercut); use anchored
  `grep -c` + baseline-0.
- **Ordinal:** ADR-079 amendment, not a new ADR — expect no new ordinal minted.

## Risks & Mitigations

- **Risk:** the redeploy Phase 3 now correctly waits for takes the full ADR-078
  cron drain (~70 min). **Mitigation:** poll ceiling 160×30 s (4800 s) ≥
  CRON_DRAIN_TIMEOUT (4200 s), inside the 90-min job timeout.
- **Risk:** `docker inspect` mid-swap → `matches=false`. **Mitigation:** the assert
  reads the frozen post-`ok` frame (new container up); baseline settle+re-read; the
  timeout STATE check re-evaluates.
- **Risk:** a future profile Docker normalizes differently than host `jq -cS`
  (64-bit `__u64` masks > 2⁵³, injected defaults). **Mitigation:** `loaded==host`
  uses the SAME host jq on both sides (skew-immune); unit case 1 + AC14's real run
  guard it. If AC14 is red, check Docker-injected defaults first.

## Deferred / Non-Goals

- **Deploy nonce** for redeploy provenance — **rejected** (not deferred): the
  assert is a STATE invariant; the timeout STATE check achieves correctness without
  it. No tracking issue.
- **Removing `write_seccomp_profile_hash` / the recorded field** — **not done and
  not scheduled**: kept permanently as an inert raw diagnostic (removal ceremony
  exceeds the payload). No tracking issue.
