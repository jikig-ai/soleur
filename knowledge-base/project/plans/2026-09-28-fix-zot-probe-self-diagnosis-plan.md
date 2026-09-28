---
title: "fix(infra): zot consumer probe names a private-net outage, and the registry liveness feeder records why it withheld a beat"
date: 2026-09-28
slug: fix-zot-probe-self-diagnosis
branch: feat-one-shot-7262-7270-zot-probe-self-diagnosis
issue: 7262
closes: [7262, 7270]
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: single-domain
---

# fix(infra): zot probe self-diagnosis (#7262, #7270)

## Overview

Two observability defects on the zot image-pull path, shipped as one PR. The web-host consumer
probe mislabels every private-network outage as an "unexpected code", because curl's own `000`
and the `|| echo 000` fallback concatenate into `000000`. The registry-host liveness feeder
withholds a Better Stack beat when zot does not answer, but records nothing about why, so a
flap cannot be diagnosed off-box.

The consumer-probe fix is one line, plus a behavioural test against a dead port. The feeder fix
keeps per-boot counters in tmpfs. The existing 5-minute `SOLEUR_ZOT_DISK` row then carries
them, so the next flap can be diagnosed from one Better Stack query. It adds no new token, no
new egress and no new alarm.

## Research Insights

**Measured data** (Better Stack Uptime incidents API, Telemetry warehouse, Sentry; the research
scratchpad `phaseB-research.md` §1, re-verified on 2026-09-28 where noted):

- `web-zot-consumer-probe` SUPPRESS rows 08-13 to 09-28: 10, all web-1, and **all 10 read
  `unexpected code 000000`**. The `000` branch count is 0. Positive control: about 47
  `SOLEUR_PROBE_CANARY` rows per day on every covered day. Coverage starts 08-13 (older rows
  were lost on the 3-day free tier). web-2 rows only from 09-24.
- `soleur-registry-prd` incidents (re-pulled 2026-09-28, 129 total): **124** from
  08-03T18:22:54Z to 08-10T22:18:10Z, ended inside the `registry_luks_recut` run
  31437037877. Since then **5**, each during a registry host replace (08-16, 09-18, 09-20,
  09-22, 09-28T11:52:02Z = new boot `923f53de`). `zot_restarts` max 0 across all 7 logged boots.
- The #7270 statements "18x" and "stopped 08-05T02:33:48Z" were wrong. The next incident came
  2 min later and 99 followed. Corrected on the issue (comment 5874247334).
- Heartbeats (live): `soleur-registry-prd` 60/30, `soleur-web-zot-consumer-web-{1,2}` 180/60,
  `soleur-git-data-prd` now exists (60/180, created 09-27).
- `.github/workflows/apply-web-platform-infra.yml` is **489,842 B** against its 490,000 B cap
  (158 B headroom, measured `wc -c` 2026-09-28), so a native log alert that needs `-target=` lines
  there does not fit.
- Registry user_data: `registry-userdata-budget.sh --json` gives stored 20,408 B of 32,768
  (headroom 12,360 B) on `origin/main` 1b57de9120.

**Code facts on `origin/main` 1b57de9120:**

- `apps/web-platform/infra/web-zot-consumer-probe.sh`, the `CODE=$(curl -s -u … -w
  '%{http_code}' … || echo 000)` line inside the `else` arm: on a transport failure curl
  prints `000` AND exits non-zero, so `CODE=000000` and the `000)` arm never matches.
- `apps/web-platform/infra/cloud-init-registry.yml`, write_files `zot-liveness-heartbeat.sh`:
  probe `http://${private_ip}:5000/v2/`, ping only on `200|401`, `exit 0`, **no log, no
  state**. Its own probe uses `|| true`, so it does not have the `000000` bug.
- Same file, `zot-disk-heartbeat.sh`: one `LINE="SOLEUR_ZOT_DISK …"` assignment. The trusted
  region ends at `zot_last_err=`. `registry-boot-guard.test.sh` asserts the field list
  (derived `store_*` plus a literal list). `zot-disk-heartbeat-redaction.test.sh` checks every
  trusted-head token is `key=value` with no quote, backslash or space, and pins
  `store_escrow=… store_escrow_age_s=… host=` adjacency. `zot-image-fetch.test.sh` H7 needs
  `ghcr_blocked=… .* host=`. The redaction suite already redirects `/run/soleur-registry/` to
  a temp dir, which is why the new state file lives there.
- `/run/soleur-registry/` is created by `mkdir -p` in the LUKS-open paths. The feeder will
  `mkdir -p` it too, since the timer's `OnBootSec=30s` has no ordering on those units.
- Delivery. The consumer probe is in `server.tf` `local.host_script_files` (baked by the
  Dockerfile into the web image, checked by `host_scripts_content_hash`) and in
  `terraform_data.zot_consumer_probe_install` (SSH provisioner, web-1 only). That provisioner is
  `-target`ed by the push-triggered apply's post-bridge step. So: **web-1 on merge**. web-2
  only at its next replace, from an image built after the merge (same class as #9151).
  `cloud-init-registry.yml` is in `registry-host-replace-dispatch.yml`'s push paths, so the
  merge delivers a **registry host replace**.
- The registry's container-log shipper ships only `CONTAINER_NAME=zot`. A `logger` line from
  the feeder would stay on a no-SSH host, so nobody could read it.

**Learnings applied:**

- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`: curl
  stubs must model `-w`/`-f`/exit codes. The existing liveness suite's stub already does.
- `2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md`: new
  fields go before the first `zot_last_err=` and are charset-guarded.
- `2026-09-21-curl-retry-flags-…`: exit codes are measured, not inferred from flags. The
  ping-fail counter keys on the ping curl's real exit status.

**Premise Validation.** #7262 and #7270 are OPEN, and no PR closes them (`gh issue view`). The
cited bug line exists on `origin/main`. The "fix on `feat-one-shot-resend-inbound-webhook-500`"
never merged. #7247 and #7341 (the 08-03 to 08-10 cause) are closed and resolved by the
08-10 recut. The #7270 claim that no git-data heartbeat exists is stale (it exists now). No
ADR rejects per-boot counters on the heartbeat row. ADR-184 rejected Vector on this host,
which is consistent with adding no new shipper.

**Property List.**

- P1. A web host that cannot reach zot over the private network reports `000 … UNREACHABLE`,
  not `unexpected code`.
- P2. After a `soleur-registry-prd` incident, one Better Stack query tells apart: zot did not
  answer (and with what code), zot answered but the beat's egress failed, the feeder stopped
  running, or the beat was sent on time (a Better Stack / timer-margin artifact).
- P3. An operator paged by `soleur-web-zot-consumer-*` or `soleur-registry-prd` has a no-SSH
  runbook.
- P4. The rate-alarm and threshold questions in both issues are decided on measured data and
  recorded.

**Cut List.**

- `logger -t zot-liveness-heartbeat` line → P2 → nothing off-box can read it (the shipper takes
  only `CONTAINER_NAME=zot`). The counters in `SOLEUR_ZOT_DISK` cover P2. Cut.
- SUPPRESS rate alarm (`logtail_exploration_alert`) → partial-degradation paging → every
  SUPPRESS row in 46 days was a planned replace, so the alarm would page on every registry
  merge. A zot crash-loop is already covered by `scheduled-zot-restart-loop.yml` and the 60/30
  beat. It also needs workflow bytes that do not exist (158 B headroom). Cut.
- Widening `soleur-registry-prd` 60/30 → fewer false pages → no false page observed: all 129
  incidents are true positives. Cut.
- A dedicated `liveness_last_miss_age_s` → P2 → the 5-minute deltas of `liveness_miss_cum`
  already place a miss in its window. Cut.
- Dropping the `|| echo 000` fallback → P1 → breaks the `-f` mutation row (c), which needs
  `404000` to stay in the catch-all. Normalize instead.

## Implementation Phases

### Phase 1 — consumer probe names the private-net outage (#7262)

1. RED: in `web-zot-consumer-probe.test.sh`, add a behavioural row that runs the real probe
   with `ZOT_ENDPOINT=127.0.0.1:1` (nothing listens there). Expect exit 0, no ping,
   `SUPPRESS ping: 000 —` and `UNREACHABLE`, and no `unexpected code`. (Kieran ran the current
   probe against it: `unexpected code 000000`, so this row is RED today.) Run it and see it fail on `main`'s probe.
2. GREEN: in the probe's live `else` arm, right after `[ -n "$CODE" ] || CODE=000`, add
   `case "$CODE" in 000000) CODE=000 ;; esac`, with a comment naming the double-write.
   Keep `|| echo 000`. Row (c) (`-f` injected, `404000` goes to the catch-all) must stay green.

### Phase 2 — the liveness feeder records why (#7270)

Revised after plan review. The field set is now five integer or code fields, with no clock
arithmetic in the reporter.

1. RED: extend `zot-liveness-heartbeat.test.sh`.
   - Render with `/run/soleur-registry/` redirected to a temp dir. This is a new seam, the same
     as the redaction suite's, with a seam-landed assert.
   - Stub the ping curl so it can fail (`STUB_PING_RC`).
   - Add a raw-template assert: the feeder block has no `${` except `${private_ip}`,
     `${liveness_heartbeat_url}` and `$${`, and no `%{` except `%%{`.
   - Rows:
     - 000 run: `miss_cum=1`, `last_miss_code=000`, no ping.
     - Then a 503 run: `miss_cum=2`, `last_miss_code=503`. Counters accumulate.
     - 401 run with the ping OK: `ok_cum` goes up by one, `miss_cum` is unchanged,
       `ping_fail_cum=0`.
     - 401 run with the ping failing (exit 22): `ping_fail_cum=1`, `ok_cum` unchanged.
     - OK ping whose stored previous-OK time is more than 75 s old: `late_ok_cum` goes up by one.
       An OK ping 60 s after the previous one leaves it unchanged.
     - Corrupt state file: counters restart from 0, and the ping still fires.
     - Unwritable state dir (the seam points under a regular file): the ping still fires, exit 0.
     - Slow state step (a `mv` stub on `$BIN` that sleeps 30 s, under the harness's `timeout 10`):
       the ping is still recorded. This is the row that goes RED if state work moves above the
       ping, since the feeder has no `set -e` and a merely failing state step would not stop it.
     - First OK after boot (no stored `last_ok_ts`): `late_ok_cum` stays 0.
   - Existing T1–T5 keep passing (non-vacuity pairing kept).
2. GREEN: in `cloud-init-registry.yml` `zot-liveness-heartbeat.sh`:
   - Capture the ping curl's exit status.
   - After the ping, run the state step in a subshell, `( … ) || true`. It must never suppress
     or delay the ping and never change the explicit final `exit 0`.
   - The state step does `mkdir -p /run/soleur-registry` and reads `zot-liveness.state`, with
     integer fields regex-validated (anything else resets to 0). It updates the file and writes
     it atomically (tmp + `mv`).
   - State: `miss_cum`, `ping_fail_cum`, `ok_cum`, `late_ok_cum`, `last_miss_code` (3 digits,
     or `none` before the first miss), plus the internal `last_ok_ts` that `late_ok_cum` needs.
     `last_ok_ts` is not emitted.
   - Also add `TimeoutStartSec=45s` to `zot-liveness-heartbeat.service`. The worst-case run is
     two 10 s curls, and this bounds a hang so it costs at most one tick.
   - No heredocs and no comment-shaped lines (a `#` then a space) inside strings (the rationale strip). Shell variables are
     written bare (`$miss`), never `$${miss}`: the liveness suite converts `$${` to `${` and
     then fails any leftover `${word}` (Kieran P1).
3. RED: in `zot-disk-heartbeat-redaction.test.sh`, add a liveness phase with its own case
   counter and a floor equal to the field count (5). `_bump_cases`, the save/restore block and
   the conservation check all learn the new `PHASE=liveness`. Add a seam-landed assert for
   `$TMP/run-soleur-registry/zot-liveness.state` (the reader must spell the path with the
   `/run/soleur-registry/` prefix the existing seam rewrites). Rows:
   - Absent state file: every `liveness_*` field is `-1`.
   - Valid state: exact values.
   - Hostile state (spaces, quotes, a 10-digit number, a non-digit code): each hostile field is
     exactly `-1`, the valid fields beside it keep their values, and the head charset contract
     holds.
   - Writer/reader vocabulary: `last_miss_code=none` (what the feeder writes before the first
     miss) reads back as `none`, and a 3-digit code reads back verbatim.
   - Every `liveness_` field precedes `zot_last_err=`. The set is derived from `LINE=`, with a
     floor of 5, one per field.
4. GREEN: in `zot-disk-heartbeat.sh`:
   - Read the state file (`timeout 5 cat | head -c 512`).
   - Validate each field (`^[0-9]{1,9}$`, and the code `^([0-9]{3}|none)$`, the exact set
     the feeder writes). Anything else, or no file, gives `-1`. No arithmetic, so no `10#`.
   - Insert `liveness_miss_cum liveness_ping_fail_cum liveness_ok_cum liveness_late_ok_cum
     liveness_last_miss_code` after `log_shipper_shipped_cum=…` and before `store_mount_src=`.
     This keeps the `store_escrow_age_s=… host=` adjacency and H7.
5. Measure `registry-userdata-budget.sh --json` before and after. The real `templatefile()`
   render must exit 0, not 2 ("unmeasurable"). Headroom was 12,360 B on `origin/main`
   1b57de9120, and the change must keep it positive. Record both numbers in the PR.

### Phase 3 — runbook, C4 note, ratchet

1. Add a section to `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
   (the runbook that already covers the `SOLEUR_ZOT_LOG` / `SOLEUR_ZOT_DISK` channels) rather
   than a new file. Title it "A zot heartbeat paged (`soleur-web-zot-consumer-*`,
   `soleur-registry-prd`)". It covers:
   - What each heartbeat proves.
   - The no-SSH readback: SQL for probe SUPPRESS rows by host and code, and the per-boot
     `SOLEUR_ZOT_DISK` `liveness_*` deltas.
   - The replace-correlation step first (`gh run list -w registry-host-replace-dispatch.yml` and
     a new `boot_id`).
   - A decision table over the deltas.
   - One line pointing at #7262/#7270 for the "no rate alarm, keep 60/30" decision.
2. `model.c4`, `zotRegistry -> betterstack` edge. Replace the stale "consumer-perspective
   reachability is unbuilt (#6438 §1)" with a statement that it is built (the web hosts'
   `web-zot-consumer-probe`, per-host heartbeats). Add one sentence saying the heartbeat carries
   the liveness feeder's per-boot `liveness_*` counters. No counts change.
3. `plugins/soleur/test/preflight-discoverability-test.test.ts`: raise `BASELINE_DECLARED_PROBES`
   by 1, with the PLACEMENT/TRUTH/NO SUBSTITUTE comment. This plan's `discoverability_test`
   declares `credentials_required`.
4. The #7270 record is already corrected (comment 5874247334, posted at plan time).

## Files to Edit

- `apps/web-platform/infra/web-zot-consumer-probe.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.test.sh`
- `apps/web-platform/infra/cloud-init-registry.yml`: the `zot-liveness-heartbeat.sh`,
  `zot-liveness-heartbeat.service` and `zot-disk-heartbeat.sh` blocks
- `apps/web-platform/infra/zot-liveness-heartbeat.test.sh`
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`

## Files to Create

None.

## Plan Review (applied)

The panel was DHH, Kieran, code-simplicity, and the CTO (domain and devex lens), plus a scoped
advisor consult.

- **Applied:**
  - `max_ok_gap_s` and `last_ok_ts` are replaced by `ok_cum` + `late_ok_cum` (CTO, DHH). A
    per-boot maximum goes stale after the first incident, and counters read as deltas with no
    age math.
  - The state step moves into a fail-open subshell, and the unit gets `TimeoutStartSec=45s`
    (CTO, advisor).
  - A raw-template escaping assert is added, and the real render must exit 0 (CTO).
  - One sentinel (`-1`) replaces three (simplicity).
  - The runbook becomes a section of the existing Better Stack runbook instead of a new file
    (DHH, simplicity).
  - The `registry-boot-guard.test.sh` field check is dropped, because the redaction suite owns
    the set (DHH).
  - The C4 consumer-edge note is cut, and the stale "unbuilt" claim is fixed instead
    (simplicity).
  - The `BASELINE_DECLARED_PROBES` bump is added to Files to Edit (simplicity).
  - Kieran: bare `$var` in the feeder; a slow-`mv` row so Guard 2 row 1 really reds; a first-OK
    row; the writer/reader code vocabulary is pinned; hostile rows pin an exact `-1`; the new
    phase counter is wired through save/restore and conservation; a seam-landed assert for the
    state path.
- **Declined:**
  - Replacing `|| echo 000` with `|| CODE=000` (DHH P1). It would also send an HTTP code
    followed by a mid-body curl failure (for example `200` then exit 28) to UNREACHABLE,
    erasing the signal that zot answered. The exact `000000` match keeps that case in the
    catch-all and leaves row (c) byte-for-byte unchanged.
  - Moving the feeder into a standalone file injected with `base64encode(file())` (advisor).
    Both registry scripts are inline `write_files` today, and their suites already render and
    execute the template text. Changing the delivery shape here would widen the diff and the
    user_data for no property this plan needs. The raw-template assert covers the escaping risk.
  - Cutting the feeder counters in favour of reading zot's request lines in `SOLEUR_ZOT_LOG`
    (simplicity). Those lines are rate-capped (`SOLEUR_ZOT_LOG_DROPPED`), and they show only
    that zot answered. They cannot show a beat that failed its egress, or a feeder that did not
    run.

## Implementation Notes (work phase, 2026-09-28)

- **State format changed from `key=value` lines to one line of six positional fields**
  (`miss ping_fail ok late_ok code last_ok_ts`). The key=value revision measured 21,292 B stored
  user_data, over `REGISTRY_GZIP_BUDGET` (21,000). ADR-185's 2026-09-28 amendment says the next
  feature must shrink rather than raise the constant. The positional form measures 20,924 B
  (headroom 11,844 against the 11,768 floor). ADR-185 has a dated addendum recording the 76 B of
  remaining slack.
- The reporter reads the line with `read -r` instead of `timeout 5 cat | head -c 512`, and validates
  each field in one loop: an integer of at most 10 digits with no leading zero, and a code of 3
  digits or `none`. Anything else is `-1`.
- The `last_ok_ts` width bug (epoch seconds have 10 digits, and the first draft allowed 9) was
  caught by the L5 row before commit.
- Mutation batteries: 4 rows on the key=value feeder, then 7 rows on the final feeder and reporter.
  All were killed: state before ping, fail-as-ok, no read-back, late never counted, reporter
  unvalidated, field after `zot_last_err`, code unvalidated.

## Open Code-Review Overlap

None. Open `code-review` issues were checked against every path above on 2026-09-28.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The risk sits on the image
  pull path. If the feeder's new block broke the ping, `soleur-registry-prd` would page with zot
  healthy. That is deploy-blocking by design (ADR-169), so a founder's release would stall until
  a follow-up replace. The design makes the ping run before any state work, and tests assert it.
- **If this leaks, the user's data is exposed via:** no user data is involved. The new fields
  are integer counters, epoch-derived ages and an HTTP status code about the registry host.
- **Brand-survival threshold:** `none`
- threshold: none, reason: the change touches registry and web-host observability scripts only.
  It carries no user data, and a failure pages the operator rather than reaching a user.

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeats soleur-registry-prd (feeder zot-liveness-heartbeat.timer) and soleur-web-zot-consumer-web-{1,2} (web-zot-consumer-probe.timer); SOLEUR_ZOT_DISK row now carries liveness_* counters"
  cadence: "60s beat (registry), 60s probe / 180s+60s heartbeat (web), 5-min SOLEUR_ZOT_DISK row"
  alert_target: "Better Stack incident -> operator email (existing heartbeat policies)"
  configured_in: "apps/web-platform/infra/zot-registry.tf (betteruptime_heartbeat.registry_prd), apps/web-platform/infra/cloud-init-registry.yml, apps/web-platform/infra/web-zot-consumer-probe.sh"
error_reporting:
  destination: "Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK direct POST; web probe stderr via Vector Source 4)"
  fail_loud: "web: '[zot-probe] SUPPRESS ping: 000 — <endpoint> UNREACHABLE'; registry: liveness_miss_cum / liveness_ping_fail_cum increase between consecutive SOLEUR_ZOT_DISK rows of one boot_id"
failure_modes:
  - mode: "private-net path web -> zot down"
    detection: "web-zot-consumer-probe SUPPRESS row with code 000 (was mislabelled 000000); heartbeat absence after 240 s"
    alert_route: "soleur-web-zot-consumer-web-N incident"
  - mode: "zot not answering on the registry private IP"
    detection: "liveness_miss_cum delta > 0, liveness_last_miss_code = 000 or 5xx"
    alert_route: "soleur-registry-prd incident (90 s)"
  - mode: "zot fine, beat egress to Better Stack failing"
    detection: "liveness_ping_fail_cum delta > 0 with liveness_miss_cum flat"
    alert_route: "soleur-registry-prd incident; runbook marks it a false-positive arm"
  - mode: "feeder timer stopped"
    detection: "liveness_ok_cum, liveness_miss_cum and liveness_ping_fail_cum all flat across consecutive rows of one boot_id"
    alert_route: "soleur-registry-prd incident"
  - mode: "beat sent on time, incident anyway (timer margin / vendor side)"
    detection: "liveness_late_ok_cum delta > 0 with miss and ping-fail deltas 0 (beat left late); all deltas nominal (ok_cum +~5 per row) means the gap was vendor-side"
    alert_route: "soleur-registry-prd incident; runbook classifies it"
logs:
  where: "Better Stack Telemetry, source 2457081 (remote + s3 archive)"
  retention: "paid tier since 2026-08-16 (rows from 2026-08-13 retained)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK"
  expected_output: "liveness_miss_cum="
  credentials_required: "Doppler soleur/prd_terraform BETTERSTACK_QUERY_* read connection — Better Stack log content is readable only through the authenticated ClickHouse connection; no unauthenticated endpoint exposes it"
```

## Encryption Posture

```yaml
at_rest:
  - store: /run/soleur-registry/zot-liveness.state on the registry host (tmpfs, reset every boot)
    mechanism: plaintext-exception
    evidence: five integers, one epoch timestamp and a 3-digit HTTP status about the host's own zot; no secret, credential or personal data; tmpfs so it never reaches the volume or root disk
    defends_against: nothing needs defending for confidentiality; integrity is bounded by the reader's regex validation (a hostile value becomes -1, never free text in the trusted region)
    does_not_defend: root on the registry host can forge the counters (same trust as every other SOLEUR_ZOT_DISK field)
    disclosed_as: not-publicly-claimed
    live_verification: available — the fields appear in SOLEUR_ZOT_DISK after the replace
in_transit:
  - connection: registry host -> Better Stack Logs ingest (existing SOLEUR_ZOT_DISK POST, unchanged; no new connection)
    enforced_at: apps/web-platform/infra/cloud-init-registry.yml zot-disk-heartbeat.sh post()
    tls: HTTPS (curl default, TLS 1.2+)
    cert_verification: on
    does_not_defend: a compromised Better Stack account reading the rows
    disclosed_as: not-publicly-claimed
exception:
  justification: the only new store is a tmpfs file of non-confidential operational counters
  tracking_issue: "#7270"
  reevaluate_when: the state file ever holds anything other than counters, timestamps and status codes
  expires_on: 2026-12-27
```

## Guard Contract

### Guard 1 — consumer probe classifies a transport failure as 000

**Property.** When the probe's curl gets no HTTP response, the verdict printed is the `000`
UNREACHABLE branch and no ping is sent.

**Assembly.** The single `CODE=` capture in the probe's live arm, the normalization after it,
and the `case "$CODE"` dispatch. The seam arm (`SOLEUR_ZOT_PROBE_STATUS_OVERRIDE`) bypasses the
capture, so it cannot prove this property. Only the behavioural dead-port row can.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete the `000000) CODE=000` normalization | RED (dead-port row prints `unexpected code 000000`) |
| 2 | point the dead-port row at the live mock port instead (the suite's own dispatch) | RED (the row asserts `UNREACHABLE`; a 200 verdict fails it) |
| 3 | change the `000)` arm's message to drop `UNREACHABLE` | RED |
| 4 | drop `|| echo 000` (a tempting "simpler" fix) | RED on row (c): `-f` then yields `404` and the EMPTY/DETACHED verdict |

### Guard 2 — liveness counters are recorded without ever touching the ping

**Property.** Each feeder run adds exactly the right counter for its outcome, and nothing in
the state work can suppress or delay a ping that the probe earned, or change the exit code.

**Assembly.** The feeder's probe `case`, the ping curl's exit status, and the one state write
after it. The state path is the only filesystem write in the feeder.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | move the state update above the ping | RED (slow-`mv` row: `timeout 10` kills the feeder before the ping) |
| 2 | increment `miss_cum` on a 401 | RED |
| 3 | count a failed ping as OK (ignore the ping's exit status) | RED (`ping_fail_cum` row) |
| 4 | reset counters every run (no read-back) | RED (the second-miss row expects 2) |
| 5 | write to the rendered path without the seam (suite dispatch) | RED (the seam-landed assert) |

### Guard 3 — liveness fields in the trusted region, charset-safe

**Property.** Every `liveness_` field is emitted before `zot_last_err=`, as `key=value` with
no space, quote or backslash, whatever the state file contains.

**Assembly.** The single `LINE="SOLEUR_ZOT_DISK …"` assignment (the emit chokepoint) and the
reader block that sets the five `LIVENESS_*` variables (the emit chokepoint's only liveness input). The field set is derived from `LINE=`,
not listed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | move one `liveness_` field after `zot_last_err=` | RED |
| 2 | pass a state value through unvalidated | RED (hostile-state row: space or quote in head) |
| 3 | add a sixth `liveness_` field after five compliant ones, placed after `zot_last_err` | RED (derived set) |
| 4 | derivation returns zero fields (suite dispatch) | RED (floor 5, printf + exit) |

## Acceptance Criteria

- [ ] AC1: `bash apps/web-platform/infra/web-zot-consumer-probe.test.sh` passes, and the
  dead-port row fails against `origin/main`'s probe. The RED run is recorded in the PR.
- [ ] AC2: `bash apps/web-platform/infra/zot-liveness-heartbeat.test.sh` passes with the new
  counter rows, and T1–T5 are unchanged.
- [ ] AC3: `zot-disk-heartbeat-redaction.test.sh`, `registry-boot-guard.test.sh` (unchanged),
  `zot-image-fetch.test.sh` and `registry-userdata-budget.test.sh` pass.
- [ ] AC4: `registry-userdata-budget.sh --json` exits 0 through the real `templatefile()` render
  (not 2), with positive headroom. Before and after numbers go in the PR.
- [ ] AC5: the new `betterstack-log-query.md` section has the no-SSH SQL, the replace-correlation step, the
  liveness decision table, and the "no rate alarm, keep 60/30" decision with numbers.
- [ ] AC6: post-merge, the new registry boot's `SOLEUR_ZOT_DISK` rows carry all five
  `liveness_*` fields, with `liveness_ok_cum` rising between consecutive rows and `zot_image_fetch=ok`.
- [ ] AC7: post-merge, web-1's `/usr/local/bin/web-zot-consumer-probe.sh` carries the fix
  (the push apply's `zot_consumer_probe_install` step succeeded). web-2 is stated as pending its
  next replace.
- [ ] AC8: the PR body has `Closes #7262` and `Closes #7270`, and records the rate-alarm and
  threshold decisions.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO approved the plan with changes; overall risk is low to medium. It
confirmed that ping-first ordering is right, but the state step also needs a bound, because a
hang loses the next tick. It flagged three things:

- The sed-based render in the liveness suite cannot catch a bare `${x}`.
- `max_ok_gap_s` goes stale after the first incident.
- The merge must wait for #9147's replace (dispatch run 36450948310) and `zot_image_fetch=ok`.

All three are applied (see Plan Review). No other domain is touched: no user data, no
user-facing surface, no spend, no legal text.

## Test Scenarios

- Given nothing listens on 127.0.0.1:1, when the probe runs, then it prints `SUPPRESS ping:
  000 — 127.0.0.1:1 UNREACHABLE` and exits 0 without pinging.
- Given `-f` is injected, when probing a missing repo, then `404000` lands in the catch-all
  (row c, regression).
- Given the liveness state holds `miss_cum=1`, when zot returns 503, then `miss_cum=2` and
  `last_miss_code=503`.
- Given zot answers 401 and the ping curl exits 22, then `ping_fail_cum` goes up by one and
  `last_ok_ts` is unchanged.
- Given the state file holds `miss_cum=1 "x`, when the reporter runs, then the trusted head has
  no quote and `liveness_miss_cum=-1`.

## Dependencies & Risks

- **Merge ordering.** The merge fires a registry replace. Do not merge until #9147's replace
  (dispatch run 36450948310) has finished and the new boot shows `zot_image_fetch=ok`, with no
  `apply-web-platform-infra.yml` run queued or in progress.
- Expected at merge: one `soleur-registry-prd` incident lasting seconds, and 2 SUPPRESS rows
  per web host during the replace. The runbook covers this.
- web-2 does not get the probe fix until its next replace (image-baked copy, #9151 class).
