---
title: "fix(infra): zot log shipper cap-exempts the real PatchBlobUpload error line (classify on the parsed func field)"
date: 2026-10-10
slug: zot-shipper-cap-exempt-patchblobupload-func
branch: feat-one-shot-9373-zot-shipper-cap-exempt
issue: 9373
closes: 9373
type: fix
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): zot log shipper cap-exempts the real PatchBlobUpload error line

## Overview

The registry host's log shipper (`/usr/local/bin/zot-log-shipper.sh`, rendered from
`apps/web-platform/infra/cloud-init-registry.yml`) rate-caps the zot `PatchBlobUpload` error line
instead of exempting it. Its `is_cap_exempt` arm `PatchBlobUpload*) return 0` tests the zerolog
`message` field prefix, but the live error line carries
`message:unexpected error, removing .uploads/ files` and names the handler only in `func:`.
The arm has therefore never matched real traffic; the fixture that "covers" it (T9 in
`zot-log-shipper.test.sh`) uses a message shape that zot does not emit, so the suite stayed green
over a dead arm.

Fix: carry the parsed top-level `func` field through the shipper's one-jq-per-tick record and
classify the upload error line on it. Update the stale comments, the test fixtures, and the two
informational counters that share the stale shape. Delivery is a gated registry-host replace
(ForceNew `user_data`), explicitly authorized for this PR by the operator on stated conditions
(Phase 4/5).

## Research Insights

### Premise validation (Phase 0.6)

- #9373 is OPEN, not closed by any PR (`closedByPullRequestsReferences` empty). Its sweeper probe
  `scripts/followthroughs/zot-shipper-exempt-func-9353.sh` reads `TRANSIENT reason=not-yet-func-keyed`
  on every daily run since 2026-10-01, so the premise (arm not func-keyed) still holds on `origin/main`.
- Cited artifacts exist on `origin/main`: `is_cap_exempt` (cloud-init-registry.yml, "PatchBlobUpload*)"
  arm), T9 fixture ("PatchBlobUpload i/o timeout"), `n_patch` in `zot-log-channel-7440.sh`.
- #7258 (the follow-on the brief says not to plan) is an unrelated open issue; it is not in this plan.
- ADR corpus grep (`ADR-184`, `ADR-190`, `ADR-096`, `ADR-169`): no ADR rejects classifying on a
  parsed field; ADR-184 describes the four exempt classes without pinning the key. No ADR conflict.
- The brief's "known benign shape" (client-abort `unexpected EOF`) is treated in the next subsection.

### What exactly the issue wants cap-exempted (measured against Better Stack, 2026-10-10)

The real line, as emitted by zot v2.1.22 and shipped quote-stripped (from the SOLEUR_ZOT_DISK
`zot_last_err` echo, 2026-10-10T02:37:47Z), is the zerolog object:

```
{"time":"…","level":"error","message":"unexpected error, removing .uploads/ files",
 "error":"unexpected EOF","caller":"zotregistry.dev/zot/v2/pkg/api/routes.go:2190",
 "func":"zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload","goroutine":369}
```

Findings, each with its source:

1. `func` is a top-level field on EVERY zot line, not only errors (7-day pull of 2,000 SOLEUR_ZOT_LOG
   rows: `func:...SessionLogger.func1.1` on 1,047 HTTP API rows, `...basicAuthn` on 731,
   `...retention.logAction`, `...gc.GarbageCollect.*`). So classification must match the handler's
   `func` value, not the mere presence of `func`. The handler suffix is `(*RouteHandler).PatchBlobUpload`.
2. In the same 2,000 rows there are ZERO rows containing `PatchBlobUpload` (and zero level-error
   rows): the line is rate-capped today, exactly as the issue states. The only place it is visible is
   the SOLEUR_ZOT_DISK heartbeat's `zot_last_err` echo.
3. What is exempted is the **PatchBlobUpload error line in all its error shapes** (`error:unexpected EOF`
   and `error:read tcp …: i/o timeout`, see ADR-190). The `unexpected EOF` shape is the benign client-abort
   case (4 events in the last 24 h, matching the brief), but it is NOT filtered out, for three
   measured reasons: (a) the 2026-09-28 `unexpected EOF` named in the issue IS the evidence row the issue
   was filed for (paired with a 5m55s PATCH 500); (b) a `func`-keyed arm cannot, and should not,
   discriminate the `error` text, since the classifier's whole job is to keep the evidence class alive
   through a flood and an EOF vs deadline split is the probes' job (`zot-upload-ceiling-7556.sh` n1 counts
   only rows that also contain `i/o timeout`; EOF rows are explicitly out of scope there); (c) cost is
   negligible: 4/day against a 17-per-5-min exempt lane (~4,900/day) and, with the sub-quota below, at
   most 8 per tick.
4. `is_cap_exempt`'s message-prefix arm `PatchBlobUpload*` matched nothing in 7 days of real rows; the
   comment that says "Measured, zot emits … message:PatchBlobUpload i/o timeout" is not supported by
   telemetry. It is replaced, not kept (a dead arm is the defect that hid this).
5. Shape of the shipped row (needed for the 7440/7341 counters): quote-stripped, colon-joined, `func:`
   immediately followed by `,goroutine:N}`.

### Property List and Cut List (Phase 0.6b)

Properties:

- P1. A genuine `PatchBlobUpload` error line survives the per-tick ordinary cap.
- P2. Only a line zot itself attributes to that handler (parsed top-level `func`) can buy P1; no
  client-controlled byte (path, header, user-agent, journald fragment) can mint it.
- P3. P1 cannot starve crash evidence (panic / fatal) out of the exempt lane, and cannot exceed the
  exempt ceiling (bounded egress on the shared Better Stack source).
- P4. The tests exercise the REAL line shape, so a future shape drift reddens instead of passing on a dead arm.
- P5. The change reaches the running host (replace) and is observable from telemetry only.

Cut list (mechanism -> property -> what already covers it):

- A `level:error` gate in the shipper -> P2 -> `func` is zot-set and handler-specific, errors are the only
  lines that handler emits at the production log level; the exempt ceiling bounds any surprise. Cut.
- Discriminating EOF from i/o timeout in the shipper -> none the issue asks for -> the 7556 probe already
  splits them by `i/o timeout` substring. Cut.
- A new follow-through probe for live delivery of the arm -> P5 -> the existing sweeper probe
  `zot-shipper-exempt-func-9353.sh` covers "merged"; telemetry in Phase 5 covers "deployed". Cut.
- Keeping the dead `PatchBlobUpload*` message arm "for safety" -> none -> 0 matches in 7 days. Cut.
- ADR amendment -> none; Phase 2.10 detection does not fire (no architectural decision; the runbook row
  is corrected instead).

### Institutional learnings applied

- `2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed.md`: `fromjson?` needs the parentheses;
  jq `--unbuffered`; a capped row is decided and accounted; adversarial fixtures. The new jq field MUST
  follow the `(($j.func?) // null) | s` shape or one plaintext line drops the whole record.
- T19/T20 in `zot-log-shipper.test.sh` (arity pin, sentinel, forged-fragment, anchored path): the new
  field widens the TSV record, so `read -r` arity and the `| s)` count must move in the SAME edit.
- `2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md`: test the rendered program
  (the suite already renders through the `$$`/strip pipeline), not a grep of the YAML.
- `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`: user_data size is a hard gate (below).
- `2026-07-11-col0-templatefile-directive-breaks-raw-yaml-parsers-sweep-all.md`: never write `${` or `%{`
  in the template (comments included); write `$${` for a literal brace expansion.
- betterstack-log-query runbook (~L786-830): `boot_id` drift alone is not delivery evidence; require the
  heartbeat's own fields too. Also guard the `zot_restarts=` extraction against an empty match.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: "update the comments at ~964, ~1259 and ~1476" | In `cloud-init-registry.yml` the stale text is at ~1259 (CAP_EXEMPT comment), ~1476 (message-shape claim) and ~1506 (the `PatchBlobUpload` "already exempt above"). `~964` in the issue is a line number in `zot-log-shipper.test.sh` (T19 header comment, ~964), not in the YAML | Edit all four, by content anchor, not line number |
| Issue: fixture at "~521" | `zot-log-shipper.test.sh` T9 builds `{"message":"PatchBlobUpload i/o timeout"}` at L521 and asserts the class by `grep -qF 'PatchBlobUpload'` on the shipped POST body | Replace with the real shape; assert on `removing .uploads/ files` AND `func:` so the assertion cannot be satisfied by the heartbeat echo |
| Issue: "7440 counter" counts `message:PatchBlobUpload` | `zot-log-channel-7440.sh` ~L465 yes. The SAME defect exists in `zot-fill-rate-7341.sh` ~L363 (`mf.startswith("PatchBlobUpload")`, where `mf` is the parsed message) | Fix both counters (both informational, neither feeds a verdict) |
| Brief: "expect zot-fill-rate-7341 PASS" post-replace | The probe grades a boot-scoped history span; baseline today is `TRANSIENT span=18.6h_of_history_under_24h … boot=04d90de2` (pre-merge, same boot as the earlier replace). A fresh boot restarts the span, so `PASS` cannot appear within an hour of the replace | Phase 5 contract: 7341 must not FAIL; `TRANSIENT reason=span…` is the expected, reported state; PASS is re-read >= 24 h later (the daily sweeper already runs it). Disclosed, not forced |
| Brief: "expect zot-upload-ceiling-7556 PASS" | Baseline today: rc=0 PASS. Its n1 counts only `level:error` rows that ALSO contain `i/o timeout`, so the newly shipped EOF rows cannot flip it; other 5xx at EOF latency are explicitly ungraded | Phase 5 expects PASS; a TRANSIENT with a named reason is reported verbatim, a FAIL stops the run |
| `registry-userdata-budget` slack | `REGISTRY_GZIP_BUDGET = 21_000` vs 20,932 stored recorded in the test, 20,944 measured here today, so ~56-68 B of slack; the test comment says "the next registry-host addition needs a structural shrink" | Phase 2 budget step: measure with the terraform-authoritative script before and after; net-negative edits first (the removed arm); raise the tripwire constant only with a recorded measurement, staying far below the 24,767 B policy ceiling (cap 32,768 B, 11,824 B real headroom) |

## Problem Statement

A failed or aborted blob upload is the diagnostic evidence class the exempt lane exists for. Because
the arm never matched, the error half of every upload failure is dropped by the ordinary cap whenever
the channel is busy, and the `#7556` probe had to be re-based on the paired HTTP API row (PR #9353).
The error row carries `error:` (EOF vs i/o timeout), `caller:` (code site) and the `.uploads/` cleanup
fact that the HTTP row does not.

## Proposed Solution

All shipper changes are inside the `/usr/local/bin/zot-log-shipper.sh` heredoc in
`apps/web-platform/infra/cloud-init-registry.yml`:

1. **Carry `func`.** Widen `JQ_TICK` by one sentinelled field `((($j.func?) // null) | s)` (appended
   after `path`), and widen the `read -r` list by `zfunc` in the same edit. The TSV sentinel `-` for an
   absent field is already the contract; no restore line is needed because `-` matches no arm.
2. **Classify on it.** `is_cap_exempt` takes `$2` = func, bound as `local func="$2"` and tested as
   `case "$func" in`. The variable MUST be literally named `func`: the closing-criterion probe
   `zot-shipper-exempt-func-9353.sh` greps the comment-stripped function body for `\bfunc\b`, and the bare
   `"$2"` / `(*RouteHandler)` text contains no such word (a `_func` name does not match either, since `_` is
   a word character). Remove the dead `PatchBlobUpload*)` message arm. Add the arm
   `*"(*RouteHandler).PatchBlobUpload") return 2 ;;` (quoted so the parentheses and star are literal;
   suffix-anchored so a zot module-path bump `…/v3/…` still matches). Keep the function body free of any line
   that is exactly a closing brace other than its own end (the probe's awk stops at the first one).
3. **Routing decision (D2): the func-keyed row is admitted through the existing upload-evidence
   sub-quota, not the shared crash lane.** `is_cap_exempt` returns `2` for it (0 = shared lane as today,
   1 = ordinary); the call site maps rc 2 to `_exempt=1; _upload_only=1`. Rationale: the #7555 review
   reproduced a failing multi-layer push filling the 17-slot lane and starving a concurrent panic
   (the R12 priority inversion); that is precisely what an arm which was dead until now would
   re-open the moment it goes live. The error line is the other half of the same upload pairing the
   sub-quota (8 per tick) was sized for. Alternative considered and rejected: `return 0` (literal
   reading of the issue): simpler by one line, but 17 `PatchBlobUpload` lines would starve a panic in
   the same tick. Crowding the HTTP half is not a risk to the probes: the 7556 grading signal (n2) is
   presence of ANY deadline-shaped 5xx row, and 4 pairs per tick survive an 8-slot quota.
4. **Call site (explicit restructure; rc 2 is "false" inside a bare `if`/`elif`, so a bare edit would
   silently route the row to the ordinary cap).** Replace the `if is_cap_exempt "$_zclass"; then … elif
   is_upload_failure_evidence …` head with:
   `_upload_only=0; is_cap_exempt "$_zclass" "$zfunc"; _cx=$?` then
   `if [ "$_cx" = 0 ]; then _exempt=1` / `elif [ "$_cx" = 2 ] || is_upload_failure_evidence "$zstatus" "$zpath"; then _exempt=1; _upload_only=1` /
   `else _exempt=0; fi` (the shipper runs `set -uo pipefail`, no `-e`, so a non-zero return is harmless; the `_upload_only=0` initialisation that follows today's head moves above it). The rest of
   the admission block is unchanged. The tri-state return is the cheapest shape that keeps the func
   test INSIDE `is_cap_exempt` (the issue's closing criterion and the 9353 probe read that body); a separate
   predicate would be boolean but would leave the probe unsatisfiable.
5. **Comments (free of user_data bytes).** `registry_rationale_strip` removes whole-line `#` comments at
   render, so the three stale comments (CAP_EXEMPT, "Measured, zot emits …", "already exempt above") and
   the new rationale cost zero stored bytes. Never write `${` or `%{` in them.

### Why no `level` gate and no EOF filter

See Research Insights finding 3 and the Cut List. Summary: `func` is zot-set and handler-specific;
the sub-quota and exempt ceiling bound everything; the discriminator between EOF and deadline lives in
the probes.

## Technical Considerations

### Templating and render path

- Template syntax: only `${`/`%{` are special; the new code uses `"$2"`/`"$zfunc"` (plain `$`), no brace
  expansion. jq's `$j` is already inside a single-quoted string and has no brace.
- The suite renders the shipper through the real `$$` unescape + strip pipeline, so T-tests execute the
  program the host runs.

### user_data size (hard gate; blowing it strands the sole registry on the replace)

- Hetzner cap 32,768 B; `registry-userdata-budget.sh --json` today: stored 20,944 B, headroom 11,824 B
  (measured in this planning run). Test tripwire `REGISTRY_GZIP_BUDGET = 21_000` in
  `plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- Estimated delta: +~70 raw B of code (jq field, read var, call arg, new case arm) minus the removed
  arm (~45 B): net +20-40 B raw, ~+15-35 B gzipped. Likely fits in the ~56 B slack; MUST be measured, not
  assumed. If the model exceeds 21,000, raise the constant to the measured value plus a small margin with
  a dated comment in the established style (precedent: 20_000 -> 21_000 in #8714). Do not touch the 8,000 B
  headroom policy.
- Note the dispatcher's delta gate decides on RENDERED bytes: this PR is a real code change so it delivers.
  Comment-only edits would not (that is why all prose is comment lines).

### Blast radius of the replace (disclosed; authorized by the operator for this PR)

- The merge fires `registry-host-replace-dispatch.yml` (push to main on `cloud-init-registry.yml`), which
  renders at the delivery watermark and head, runs the read-only preflight, then dispatches
  `apply-web-platform-infra.yml -f apply_target=registry-host-replace` (job `registry_host_replace`,
  `environment: infra-privileged`, gate requires `store_destroyed==0`: the volume is preserved).
- During the replace the registry is dark: running web containers keep serving; deploys wait; cold-boot
  pulls fall back. No other host is replaced. web-1, web-2, git-data and inngest hosts are not touched
  (their cloud-init files are not in the diff).
- Constraints carried verbatim from the brief: preflight clean BEFORE merge, merge-queue to MERGED, replace
  only via the dispatcher, no plain web-host-replace, no `--manual`, no `[ack-destroy]` in any commit body,
  verification from telemetry only (no SSH).

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is edited. `hcloud_server.registry.user_data` changes by rendering
(`base64gzip(replace(templatefile("cloud-init-registry.yml", …), local.registry_rationale_strip, ""))`).
No new variables, providers or secrets.

### Apply path

(b) `terraform apply -replace` of the registry host through the existing, gated
`registry-host-replace` job, volume preserved (state on the persistent volume). Expected downtime: the
replace window of the registry only (minutes); precedent: the #9252 / #9795 replaces.

### Distinctness / drift safeguards

No dev/prd distinctness change. The pre-replace gate (`registry_host_replace_gate`) refuses on
`store_destroyed != 0`. Terraform's own base64gzip is the size authority.

### Vendor-tier reality check

None: no new vendor resource (Better Stack source 2457081 is shared and unchanged; the change reduces
no cap, it only re-routes ~4 rows/day into the lane).

## Encryption Posture

Skipped: the change introduces no persistent store and no new cross-component connection. It edits a
shipper that already exists on an already-provisioned LUKS-backed host; the shipped rows pass through the
same `redact()` and `sanitize()` as before (the func-keyed row is not exempt from redaction; only from
the rate cap).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly in the product. A broken replace leaves
  the registry dark: deploys wait and cold-boot pulls of new web hosts degrade until the re-fire per the
  dispatcher runbook; running containers keep serving. A broken shipper edit would silently lose evidence
  rows, never customer data.
- **If this leaks, the user's data is exposed via:** no new vector. The newly exempt row is a zot error
  line (`error`, `caller`, `func`, `goroutine`, no headers) that still goes through `redact()` and
  `sanitize()`; no customer content is in it.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no single user's data or
  money is reachable from this surface and the replace preserves the volume; not `none` because it is a
  production host replace of the sole pull path.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK heartbeat row (boot_id, zot_restarts, log_shipper_post_fail, log_shipper_dropped_cum, log_shipper_shipped_cum) plus SOLEUR_ZOT_LOG shipper rows; a missing row IS the alert
  cadence: 5 minutes (heartbeat), 5-minute shipper tick
  alert_target: Better Stack heartbeat monitor on the registry host (zot-registry.tf betteruptime_heartbeat) and the existing scheduled-zot-restart-loop workflow
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (reporter + shipper) and apps/web-platform/infra/zot-registry.tf (heartbeat resource)
error_reporting:
  destination: Better Stack source 2457081 via the shipper's own POST; shipper failures surface as log_shipper_post_fail in the heartbeat and as SOLEUR_ZOT_LOG_DROPPED rows with a reason
  fail_loud: SOLEUR_ZOT_LOG_DROPPED reason=exempt_cap (new func-keyed rows over quota are accounted, never silent); jq missing exits 1 with a stderr message (T18)
failure_modes:
  - mode: func field not parsed (jq change wrong) so the arm never fires
    detection: after the replace, a SOLEUR_ZOT_LOG row with func:...PatchBlobUpload appears within the next upload error; before that, the unit test T21 reds in CI; the 9353 sweeper probe reads the merged file
    alert_route: CI red on the PR; sweeper issue comment on #9373
  - mode: TSV arity drift corrupts every record (field shift)
    detection: T19 arity pin fails in CI; on host, shipped_cum stops growing while dropped_cum grows (heartbeat fields)
    alert_route: CI red; zot-fill-rate / heartbeat fields in the scheduled probes
  - mode: user_data over 32,768 B strands the registry after destroy
    detection: registry-userdata-budget job in infra-validation.yml and the dispatcher's head-render gate (gate-failed verdict), plus the Phase 2 local measurement
    alert_route: required CI check fails; dispatcher verdict comment on the PR
  - mode: replace does not complete or the host boots with a bad shipper
    detection: Phase 5 telemetry (new boot_id, zot_restarts=0, post_fail=0); dispatcher verdict kind (apply-failed, unverified)
    alert_route: dispatcher verdict comment on the PR/tracker; heartbeat-absent page
logs:
  where: Better Stack source 2457081 (SOLEUR_ZOT_DISK, SOLEUR_ZOT_LOG, SOLEUR_ZOT_LOG_DROPPED), journald on the host (not read; no SSH)
  retention: Better Stack warehouse retention (7-day windows are queried by the probes)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK --limit 5
  expected_output: SOLEUR_ZOT_DISK
  credentials_required: BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD via Doppler soleur/prd_terraform — the warehouse read connection is credential-gated and has no unauthenticated substitute
```

Affected-surface note (blind surface, plan 2.9.2): the registry host is non-inspectable (no SSH by
policy). The in-surface probe is the shipper's own output: a shipped `SOLEUR_ZOT_LOG` row whose body
contains `removing .uploads/ files` AND `func:…(*RouteHandler).PatchBlobUpload` discriminates all three
competing hypotheses in one row (arm live / arm dead / func not parsed): present = live; absent with
heartbeat `zot_last_err` still echoing the error = classification dead; row present without `func:` =
sanitizer/jq regression.

## Guard Contract

### Guard 1 — func-keyed PatchBlobUpload exemption

**Property.** A journald line is admitted through the exempt path as upload-error evidence if and only if
zot's own parsed top-level `func` ends in `(*RouteHandler).PatchBlobUpload`, it never displaces crash
evidence beyond the upload sub-quota, and no client-controlled byte can satisfy it.

**Assembly.** One chokepoint: the single call site of `is_cap_exempt` in the shipper's read loop (the
`while IFS=$'\t' read -r …` body). Members that must flow through it: the `func` JQ field, the `read -r`
variable, the call argument, and the rc-2 mapping to `_upload_only`. Verified by grep before editing that
`is_cap_exempt` has exactly one call site (`is_cap_exempt "$_zclass"`) and `JQ_TICK` exactly one definition;
a second call site or a second jq program makes this guard incomplete and must be added to the matrix.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the func arm from `is_cap_exempt` (or restore the message-prefix arm) | RED: T21 real-line fixture is dropped by the cap |
| 2 | Drop `"$zfunc"` from the call site (the guard's own dispatch) while leaving arm and jq field intact | RED: T21 real-line fixture dropped; T21 also asserts the shipped row is non-empty so "0 rows, exit 0" cannot pass |
| 3 | Add a non-matching func (`(*RouteHandler).GetBlob`, `…SessionLogger.func1.1`) AFTER a compliant PatchBlobUpload line in the same tick; mutate the arm to a substring/`*PatchBlobUpload*` match | RED: T21 negative row (a GetBlob error line under flood must be capped) |
| 4 | Widen the arm to match the raw line (`$1`/`$msg`) instead of parsed `$2` | RED: T21 forged row (parsed HTTP row whose User-Agent contains `(*RouteHandler).PatchBlobUpload`, and a journald fragment containing it) must stay capped |
| 5 | Change rc 2 to rc 0 (shared lane) | RED: T21 panic-behind-17 PatchBlobUpload lines row: the panic must still ship |

The widened-field case (JQ_TICK without `read -r`) is already pinned by the existing T19 arity assertion and the lane-accounting case by S3, so neither is duplicated as a matrix row.

**Harness rows:**

- Harness RED row (edit to the SUITE): change the T21 fixture's `func` value to a non-matching handler —
  the shipped-row assertion MUST go RED; it proves the fixture, not a stub, drives the result.
- Must-PASS non-canonical row: a PatchBlobUpload line with a different module path
  (`zotregistry.dev/zot/v3/pkg/api.(*RouteHandler).PatchBlobUpload`), a different `error:` (`read tcp
  10.0.0.1:5000->10.0.0.2:52888: i/o timeout`) and a different `caller:` line number MUST ship under flood.
  RED rows cannot detect a guard that rejects everything; this row can.

**Anchor.** Not applicable in the stored-value sense: nothing compares a stored hash/count to the thing it
protects. The independent anchor for the FIXTURE SHAPE is live telemetry: the fixture is a synthesized-value
copy of the line captured from Better Stack on 2026-10-10 (field names and order from the real
`zot_last_err` echo, values synthesized per `cq-test-fixtures-synthesized-only`); the post-replace Phase 5
query is what re-anchors it to the running host.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the zot log shipper ... does not cap-exempt the real PatchBlobUpload error line" [brief] | Phase 1-2 (shipper edit), Files to Edit entries 1-2 | mapped |
| 2 | "Classify on the parsed `func` field in `is_cap_exempt`; update the comments at ~964, ~1259 and ~1476, the test fixture and the 7440 counter together." [issue #9373] | Phase 2 (comments), Phase 1 (fixtures), Files to Edit 2-4 | mapped |
| 3 | "the follow-on work on #7258 is a separate later run, do not plan it here" [brief] | Non-Goals | mapped |
| 4 | "scripts/registry-replace-preflight.sh must run clean BEFORE merge (stop and report on any unclean result)" [brief] | Phase 4 | mapped |
| 5 | "ship through the merge queue to MERGED; the replace happens only via registry-host-replace-dispatch.yml (no plain web-host-replace, no --manual, never add an [ack-destroy] line to a commit body)" [brief] | Phase 4, Acceptance Criteria (Ship) | mapped |
| 6 | "verify afterwards from telemetry only, no SSH ... expect a new boot_id, zot_restarts=0, zot-fill-rate-7341 and zot-upload-ceiling-7556 PASS" [brief] | Phase 5, Research Reconciliation row on 7341 | mapped (7341 expectation disclosed as TRANSIENT-until-24h) |
| 7 | "Do not touch web-1, web-2 or git-data hosts." [brief] | Technical Considerations (blast radius), AC | mapped |
| 8 | "Determine exactly what the issue wants cap-exempted, from the code and the issue body; verify the real log line shape against telemetry if needed" [brief] | Research Insights (what exactly) | mapped |
| 9 | "Write the plan so Test Scenarios and the post-merge verification ... are explicit." [brief] | Test Scenarios, Phase 5 | mapped |
| 10 | "The PR body must carry a canonical `Closes #9373` line. Avoid the word" [brief; the avoided word is not repeated here] | Acceptance Criteria (PR body) | mapped |
| 11 | "rely on CI for typecheck and the broad battery; the machine is contended, so use scripts/pre-push-ratchet-lane.sh plus targeted suites and disclose it." [brief] | Phase 3, Acceptance Criteria (verification disclosure) | mapped |
| 12 | "Never git stash, no pkill -f, never write to Claude Code memory, always chain `cd <worktree> &&`." [brief] | Phase 0 (process) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1 (cloud-init-registry.yml shipper) | "Classify on the parsed `func` field in `is_cap_exempt`" | asked |
| Files to Edit 2 (zot-log-shipper.test.sh fixtures and T21) | "the test fixture ... together" | asked |
| Files to Edit 3 (zot-log-channel-7440.sh counter) | "the 7440 counter" | asked |
| Files to Edit 4 (zot-fill-rate-7341.sh counter) | — | inferred — justification: it counts the same dead `message:`-prefix shape (`mf.startswith("PatchBlobUpload")`); fixing only the 7440 twin leaves the identical stale counter beside it, and the issue's own stated cause ("tests the zerolog message field prefix") applies verbatim |
| Files to Edit 5 (zot-upload-ceiling-7556.sh comments only) | "update the comments" | asked (its header/n1 comments assert "the line is not cap-exempt", false after this PR; no logic change) |
| Files to Edit 6 (betterstack-log-query.md row) | "update the comments" | inferred — justification: the runbook row states the line is rate-capped and names this follow-up; left stale it becomes false the moment the host is replaced |
| Files to Edit 7 (cloud-init-user-data-size.test.ts) | — | inferred — justification: `REGISTRY_GZIP_BUDGET` leaves ~56 B slack against ~80-100 raw B of new code; without the tripwire bump the required `test` check goes red in the merge queue |
| Files to Edit 8 (test-zot-log-channel-probe.sh C15) | "the 7440 counter" | asked (the counter change needs its own suite coverage) |
| Decision D2 (rc 2 routes the row through the upload sub-quota) | — | inferred — justification: activating a dead arm in the shared lane re-opens the R12 starvation reproduced in the #7555 review; the sub-quota is the existing mechanism for exactly this class |
| Phase 5 verification | "verify afterwards from telemetry only" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `scripts`, `tests`, `knowledge-base`, `plugins/soleur` (the size tripwire constant)
- Planned files: 8 | Estimated changed lines: ~150 (code ~25, tests ~90, comments/docs ~35)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None. (Queried open `code-review` issues for all seven planned paths; no body contains any of them.)

## Plan Review Revisions

Mechanical findings applied (panel: DHH, Kieran, code-simplicity, CTO devex lens; all P0/P1 applied):

- R1 (Kieran P0): rc 2 is "false" in a bare `if`/`elif`; the call-site restructure is now spelled out (Proposed Solution 4).
- R2 (Kieran P1, simplicity): the 9353 closing probe greps `\bfunc\b` in the function body; the parameter is now
  bound as `local func="$2"`.
- R3 (DHH, simplicity): scenarios cut from 13 to 8 (S9/S10/S11/S13 became Phase 3 commands, S5 merged into S3); mutation
  matrix cut from 7 to 5 rows (the other two duplicated T19 and S3).
- R4 (CTO P1): preflight runs in the background under Monitor, last before enqueue, repeated if stale; an explicit arm-watch
  on the async dispatcher; "merged but not delivered" is a named outcome that must not be reported as fixed.
- R5 (CTO P1): the 7341 expectation is reported as "not yet observable" with an owner and a re-read time.
- R6 (Kieran P1/P2): `tests/scripts/test-zot-log-channel-probe.sh` C15 added (the real 7440 suite); tripwire bump is probable,
  not conditional; squash-merge body/title covered by the `[ack-destroy]` ban; digest-unchanged check added to Phase 5.

No taste or user-challenge items: D2 (sub-quota routing) was endorsed by DHH and simplicity as the cheapest shape that keeps the
func test inside `is_cap_exempt`; nothing argues against the operator's stated scope.

## Non-Goals

- The follow-on work on #7258 (separate later run; not planned here).
- Filtering benign client-abort `unexpected EOF` rows out of the exemption (see Research Insights; they are
  evidence-bearing, bounded by the sub-quota, and ungraded by the probes).
- Raising or retuning any cap (CAP_PER_INTERVAL, CAP_EXEMPT_PER_INTERVAL, sub-quota) — ADR-184 defers cap
  retunes because each is another cloud-init edit and another replace.
- Fixing the sampler-echo fixtures in `zot-disk-heartbeat-redaction.test.sh` (`PatchBlobUpload i/o timeout`
  as a message): those test heartbeat REDACTION of `zot_last_err`, not classification; the string there is
  just payload. Acknowledged, left unchanged.
- Any change to web-1, web-2, git-data or inngest hosts.

## Files to Edit

1. `apps/web-platform/infra/cloud-init-registry.yml` — shipper heredoc only: `JQ_TICK` (+ `zfunc` field),
   `read -r` arity, `is_cap_exempt` (remove message arm; add func arm returning 2), the single call site
   (rc 2 -> `_upload_only`), and the four stale comment blocks (CAP_EXEMPT comment ~"Cap-exempt classes get
   their OWN generous ceiling", "Measured, zot emits …", "already exempt above", the sub-quota comment that
   says the error line sits in the shared lane).
2. `apps/web-platform/infra/zot-log-shipper.test.sh` — T9 fixture to the real shape; T19 header comment
   (~L964); new T21 section (below).
3. `scripts/followthroughs/zot-log-channel-7440.sh` — `n_patch` (~L465, plus the comment ~L863 if it names the
   message shape): count `level:error` rows whose func ends in `.PatchBlobUpload`.
4. `scripts/followthroughs/zot-fill-rate-7341.sh` — `n_patch` (~L363) and the header sentence (~L20) that says
   the channel counts `message:PatchBlobUpload`.
5. `scripts/followthroughs/zot-upload-ceiling-7556.sh` — comments only (header "not cap-exempt" claims, the
   `n1` description, the WEIGHT line at the end); classifier logic unchanged.
6. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — the `PatchBlobUpload` table row.
7. `plugins/soleur/test/cloud-init-user-data-size.test.ts` — raise `REGISTRY_GZIP_BUDGET` (PROBABLE, not
   optional: the baseline is already 20,944 B against the 21,000 tripwire; size as measured + ~500 B with a
   dated comment; see user_data size).
8. `tests/scripts/test-zot-log-channel-probe.sh` — the real suite for the 7440 probe: extend case C15 with a
   genuine func-keyed shipped row (counted) and a header-borne decoy containing the string (not counted),
   asserting the probe's `n_patch=` field.

## Files to Create

None (the plan and `tasks.md` under `knowledge-base/project/` are the only new files).

## Implementation Phases

### Phase 0 — Setup (process constraints)

- Every Bash call chains `cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9373-zot-shipper-cap-exempt && …`.
- No `git stash` (use WIP commits), no `pkill -f`, no writes to Claude Code memory.
- Capture the pre-merge baseline once: the current `boot_id` and heartbeat fields (query below) so Phase 5
  compares against a recorded value, not memory. Baseline at planning time: `boot_id=04d90de2-4644-477c-8ccd-c4efe082b9f6`,
  `zot_restarts=0`, `zot_image_digest=46f688dc2631`, 7556 PASS, 7341 TRANSIENT (span<24h).

### Phase 1 — Tests first (RED), `cq-write-failing-tests-before`

In `zot-log-shipper.test.sh` (currently 174 passed, 0 failed in ~5 s):

- T9: replace the fixture line with the real shape (below) and assert on a discriminating substring of the
  SHIPPED body (`removing .uploads/ files` + `func:`), not on the bare token `PatchBlobUpload` (the bare token
  was satisfiable by any heartbeat echo; `cq-assert-anchor-not-bare-token`).
- Add `# --- T21: func-keyed PatchBlobUpload exemption (#9373) ---` implementing the Test Scenarios below.
- Run the suite and record the RED set (T9 and the T21 positives must fail on the current code), then implement.

Real-shape fixture (field order from the 2026-10-10 capture; values synthesized):

```
{"time":"2026-01-01T00:00:00.000000000Z","level":"error","message":"unexpected error, removing .uploads/ files","error":"unexpected EOF","caller":"zotregistry.dev/zot/v2/pkg/api/routes.go:2190","func":"zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload","goroutine":369}
```

### Phase 2 — Implement (GREEN)

1. Edit the shipper per Proposed Solution 1-5.
2. `bash apps/web-platform/infra/zot-log-shipper.test.sh` — all green, count = 174 + new.
3. Measure the render: `bash apps/web-platform/infra/registry-userdata-budget.sh --json` before/after; record
   both numbers in the PR body. The vitest arm models the render with node zlib, which can differ from terraform's
   by a few hundred bytes and would surface late in the merge queue, so decide up front: if the terraform
   figure is > 20,900 B (i.e. within ~100 B of the 21,000 tripwire), raise `REGISTRY_GZIP_BUDGET` in this PR
   with a dated comment and the recorded measurement (real headroom is ~11.8 KB under the 32,768 B cap; the
   8,000 B policy ceiling is 24,767 B), rather than discovering the red in CI (Files to Edit 7). The planning-time baseline is already 20,944 B, so
   this rule triggers on the baseline: expect Files to Edit 7 to be NEEDED, sized as measured + ~500 B (the
   #8714 precedent), not an optional edit.
4. Update the 7440 and 7341 counters and the 7556 comments; run `bash scripts/followthroughs/zot-shipper-exempt-func-9353.sh`
   (expect `PASS … classifies on the func field`; exit 0) and `bash scripts/followthroughs/zot-upload-ceiling-7556.test.sh`
   plus `bash scripts/followthroughs/zot-fill-rate-7341.test.sh`.
5. Update the runbook row.

### Phase 3 — Verify locally (disclosed lane)

`apps/web-platform/node_modules` is stale and the machine is contended, so local verification is
deliberately narrow and disclosed in the PR body:

- `bash scripts/pre-push-ratchet-lane.sh` (the fast affected-ratchets lane; expect `RATCHET_LANE verdict=PASS`).
- Targeted suites: `zot-log-shipper.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `registry-render-delta.test.sh`,
  `registry-boot-guard.test.sh`, `registry-userdata-budget.test.sh`, `plugins/soleur/test/zot-http-deadlines-required.test.sh`,
  `tests/scripts/test-zot-log-channel-probe.sh` (7440 probe), the two follow-through test files above, the 9353 probe itself (`bash scripts/followthroughs/zot-shipper-exempt-func-9353.sh` must exit 0), `bash scripts/followthroughs/zot-upload-ceiling-7556.test.sh` (unchanged arms stay green), `.github/scripts/test/fixtures-validate-infra-templates.sh` if it runs offline.
- NOT run locally (CI is the authority): typecheck, vitest incl. `cloud-init-user-data-size.test.ts`, the
  broad `test` battery, `infra-validation.yml`, the required-check set. State this in the PR body.

### Phase 4 — Ship (pre-merge gates, in this order)

1. **Preflight, last gate before enqueue (after CI is green).** Run `scripts/registry-replace-preflight.sh`
   under Doppler (`doppler run -p soleur -c prd_terraform -- bash scripts/registry-replace-preflight.sh`), no
   flags, read-only. Its P3 drain-wait can last up to 2,100 s, which exceeds a foreground Bash call's 600 s
   cap, so start it with `run_in_background` writing to a scratch file and watch it with Monitor (an
   until-loop on the final `rc=` line; no poll loop, `hr-monitor-not-run-in-background-for-polling`).
   Required verdict: `verdict=CLEAR`, exit 0. ANY unclean result (refused, any predicate, exit != 0, timeout) =
   STOP and report; do not merge, do not pass `--manual`. If more than ~15 minutes pass between a clear verdict and the enqueue, or the merge queue re-runs, repeat it. This is a point-in-time check: the dispatcher
   re-runs the same preflight after merge, so a `refused` verdict there leaves main merged but undelivered
   (handled in step 3). Planning-time observation: a pre-merge run sat in P3 drain-wait behind one in-flight
   zot-writing run (concurrent PR workflows were active), so budget for the wait.
2. `soleur:ship` flow: push, PR with body containing the exact line `Closes #9373` (never in the title),
   first line of the PR body "Merging this replaces the sole registry host (volume preserved; rollback is a
   second replace, not an undo)" with the dispatcher runbook link, the Phase 2/3 measurements, the mutation
   run output, and the verification-lane disclosure; no `[ack-destroy]` line anywhere in a commit body, the PR body or the PR title (a squash merge builds the commit message from them); CI green; merge via
   the merge queue to state MERGED.
3. **Arm a watch on the async dispatch** (`hr-dispatch-async-must-arm-watch`): after MERGED, resolve the
   `registry-host-replace-dispatch.yml` push-arm run for the merge commit and the `apply-web-platform-infra.yml`
   run it dispatches, and watch both to a conclusion with Monitor (until-loop on `gh run view --json
   status,conclusion`; emit every terminal state). This plan's agent does not dispatch
   `apply-web-platform-infra.yml` by hand and does not run plain `web-host-replace`. Read the dispatcher's
   verdict comment on the PR (marker `<!-- registry-delivery run=… kind=… -->`). If the verdict is
   `refused`/`gate-failed`/`dispatch-failed`/`apply-failed`/`unverified`/`cancelled`, stop and report with the
   verdict comment, say explicitly that the change is MERGED BUT NOT DELIVERED (the `Closes #9373` and the 9353
   probe read the merged file, not the host), and leave #9373 reopened or add a delivery follow-up issue rather
   than reporting "fixed". Runbook: `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`.

### Phase 5 — Post-merge verification (telemetry only, no SSH)

```bash
cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9373-zot-shipper-cap-exempt && \
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK --limit 400 | jq -r '.raw | fromjson | .message'
```

Pass criteria, all from that output:

1. **New boot_id:** the newest row's `boot_id=` differs from the Phase 0 baseline
   (`04d90de2-4644-477c-8ccd-c4efe082b9f6`) and rows from BOTH ids may appear in the 1 h window around the replace.
   `zot_image_digest=46f688dc2631` is unchanged (separates a shipper change from an image drift).
2. **`zot_restarts=0`** on the newest rows, with `zot_uptime_s` small and growing, `state_status=running`,
   `zot_image_fetch=ok`, `ghcr_blocked=1`.
3. **Delivery is more than boot_id drift** (runbook): `log_shipper_post_fail=0` is present (not `unknown`),
   `log_shipper_shipped_cum` and `log_shipper_drop_seq` restart low on the new boot (counters reset by
   design), and `err_redact_rev=1` is unchanged.
4. **Probes** (read-only; each run via `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/<name>.sh`):
   - `zot-upload-ceiling-7556.sh`: expect exit 0 PASS (baseline PASS). A TRANSIENT with a named reason is
     reported verbatim and re-read after the next shipper ticks; a FAIL stops the run.
   - `zot-fill-rate-7341.sh`: must NOT FAIL. Expected state right after a replace is
     `TRANSIENT … span=…h_of_history_under_24h` (it was already TRANSIENT pre-merge for the same reason:
     the probe needs >= 24 h of history on the current boot). This is reported as expected, not as a pass;
     PASS is a >= 24 h re-read by the existing daily sweeper.
5. **Arm live (opportunistic, not gating):** `--grep 'removing .uploads/ files'` on SOLEUR_ZOT_LOG shows a
   shipped row with `func:…(*RouteHandler).PatchBlobUpload` once the next upload error occurs (~4/day, so it can
   be hours; absence in the first hour is NOT a failure and is not read as one).
   `zot-shipper-exempt-func-9353.sh` reading PASS on main closes #9373's tracker side; the PR's `Closes #9373`
   closes the issue at merge. Say plainly in the report that item 5 is pending an organic event.

Report format: boot_id before/after, zot_restarts, post_fail, each probe's verdict line, the dispatcher run URL,
and two explicit status lines: `7341 PASS: not yet observable (needs >= 24 h of history on the new boot; owner:
the daily follow-through sweeper, re-read at merge + 25 h)` and `arm live: pending an organic upload error`.
The brief's "expect 7341 PASS" must not survive into the summary as a claim.

## Test Scenarios

New section `T21` in `apps/web-platform/infra/zot-log-shipper.test.sh` (synthesized values, real shape) plus T9
retargeted. RED set on current `main` code (to be recorded in the PR body): S1, S2, S3, the retargeted T9,
and the raised T19 floor (`JQ_TICK` emits `-ge 6` sentinelled fields, from `-ge 5`). S4-S8 and S12's decoy half are
GREEN today by construction and are guards RED under a named mutation (matrix rows 1-5); the plan labels
them so, to keep the RED set honest. Assertions anchor on the sanitized, quote-stripped shipped body, e.g.
`removing .uploads/ files` plus `PatchBlobUpload,goroutine`, never the bare token (the heartbeat echo carries
it too). S6/S7 assert shipped-row COUNT and `reason=rate_cap` (T16 style): a forged row that is capped-through
still contains the text, so substring-absence cannot be the assertion. Rows meant to be capped (S3 GetBlob /
SessionLogger) are placed AFTER at least `CAP` ordinary rows, else they ship under the cap.

| # | Scenario | Fixture / setup | Expected |
|---|---|---|---|
| S1 | Real EOF error line survives a flood | 40 ordinary HTTP API rows, then the real-shape EOF line; `CAP_PER_INTERVAL=5` | row shipped (asserted by `removing .uploads/ files` AND `func:` in the POST body). RED today |
| S2 | i/o timeout variant (deadline sub-mode) survives | same, `error:"read tcp 10.0.0.1:5000->10.0.0.2:52888: i/o timeout"`, other `caller` line, module path `…/zot/v3/…` | shipped (must-PASS non-canonical row). RED today |
| S3 | Sub-quota bounds the class; other handlers stay capped | 40 func-keyed lines (default `CAP_UPLOAD_EVIDENCE_PER_INTERVAL=8`) plus a level:error line with `func:…(*RouteHandler).GetBlob` and the HTTP-API `SessionLogger.func1.1` flood | exactly 8 func-keyed rows shipped; remainder accounted `reason=exempt_cap`; n + shipped == 40; the GetBlob and SessionLogger rows are capped by the ordinary cap |
| S4 | Crash evidence not starved (R12) | 17 func-keyed lines then `panic: runtime error: T21SENTINEL`, `CAP_PER_INTERVAL=1` | panic ships. Mutation "rc 2 -> 0" reds this |
| S6 | Forged HTTP-API row cannot mint the exemption | 40 parsed HTTP API rows whose `headers`/`path`/`username` embed `"func":"…(*RouteHandler).PatchBlobUpload"` text (properly escaped inside strings) | capped (top-level func is SessionLogger) |
| S7 | Forged journald fragment cannot mint it | 25 invalid-JSON fragments beginning with `…,"func":"zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload","goroutine":1}` text + a genuine plaintext panic, `CAP_PER_INTERVAL=1` | fragments capped (unparsed so `zfunc` is empty), panic ships |
| S8 | Empty / absent func does not shift the record | plaintext line, a JSON line with no `func`, and a JSON line with `"func":""` interleaved with a real func-keyed line | no field shift: every row classifies independently; the real one still ships (sentinel pin) |
| S12 | Counters | one added assertion in `zot-fill-rate-7341.test.sh` and a minimal 7440 awk run on a func-keyed shipped row | `n_patch`/`patch_blob_upload` counts the real shape, and does not count an HTTP-API row quoting the string in a header |

Regression: all 174 existing `zot-log-shipper.test.sh` assertions, `zot-disk-heartbeat-redaction.test.sh`,
`registry-render-delta.test.sh`, `registry-boot-guard.test.sh`, `registry-userdata-budget.test.sh`,
`zot-http-deadlines-required.test.sh` stay green.

Integration verification (for `soleur:qa`): Phase 5 telemetry reads above; no UI.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `is_cap_exempt` classifies the func-keyed `PatchBlobUpload` line (func arm present in the function body outside comments);
      the message-prefix arm is gone; JQ_TICK and `read -r` agree at 6 fields; one call site passes `"$zfunc"`.
- [ ] `zot-log-shipper.test.sh` green with S1-S10 (RED before, GREEN after, RED set recorded in the PR body);
      the Guard Contract mutation rows 1-5 were each run once by hand and went RED (output recorded in the PR body).
- [ ] `bash scripts/followthroughs/zot-shipper-exempt-func-9353.sh` exits 0.
- [ ] `registry-userdata-budget.sh --json`: stored size before/after recorded in the PR body; `<= 32,768` with the
      8,000 B policy headroom intact; `REGISTRY_GZIP_BUDGET` raised only if measured, with a dated comment.
- [ ] Stale text corrected: the four YAML comments, T9/T19 comments, 7440/7341 counters, 7556 comments, runbook row.
- [ ] `scripts/pre-push-ratchet-lane.sh` PASS; targeted suites listed in Phase 3 green; PR body DISCLOSES that
      local typecheck/vitest/broad battery were not run (stale node_modules, contended machine) and CI is the authority.
- [ ] `scripts/registry-replace-preflight.sh` run immediately before merge returned a clear verdict (any unclean result = stop and report).
- [ ] The diff touches only the Files-to-Edit list; `git diff origin/main...HEAD --stat` shows no change under web-1/web-2/git-data/inngest cloud-init files.
- [ ] PR body contains the line `Closes #9373` (PR body, not title); no commit body contains an `[ack-destroy]` line; no word from the
      forbidden list appears in the title/body/plan.
- [ ] CI required checks green, merged via the merge queue to state MERGED.

### Post-merge (telemetry)

- [ ] Dispatcher verdict for the merge is a delivered replace (no `refused`/`gate-failed`/`apply-failed`/`unverified`/`cancelled`).
- [ ] Phase 5 items 1-3 hold (new boot_id, `zot_restarts=0`, `log_shipper_post_fail=0` present).
- [ ] `zot-upload-ceiling-7556.sh` PASS (or a named TRANSIENT reason, reported); `zot-fill-rate-7341.sh` not FAIL (TRANSIENT span<24h expected and reported; PASS re-read after 24 h by the daily sweeper).
- [ ] Final report states what is verified (replace delivered, probes) and what is pending an organic event (first shipped `func:…PatchBlobUpload` row).

## Domain Review

**Domains relevant:** Engineering (infrastructure/observability), Operations

### Engineering

**Status:** reviewed (inline by the planner; the plan-review panel below carries the independent reads)
**Assessment:** Single-surface shipper fix with a gated production host replace. Main risks are (1) user_data size slack (~56 B) and (2) re-activating a dead arm in the shared exempt lane (resolved by D2). No architectural decision (no ADR/C4 impact: no new substrate, boundary, ownership or external system; the shipper and its edges are already modeled).

### Operations

**Status:** reviewed
**Assessment:** The replace is authorized for this PR by the operator on explicit conditions, carried into Phase 4/5 verbatim. No CPO/CMO/CLO/CRO/CFO/CCO implications; no user-facing surface (Product/UX gate: NONE; no UI-surface file in the Files lists). GDPR gate: no new data class (zot error line, redacted and sanitized as before); not a regulated-data surface.

## Hypotheses

Not a connectivity incident. The brief names SSH only as a prohibition (no SSH, telemetry only), so the
firewall-first L3->L7 checklist has nothing to diagnose; no sshd/fail2ban hypothesis is proposed.

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| user_data crosses the tripwire (~56 B slack) or, worse, the 32,768 B cap | Medium for the tripwire, very low for the cap | measure with terraform's base64gzip before/after; net-negative design; raise tripwire only with measurement; dispatcher head-render gate refuses over-cap |
| Preflight refuses (P1 local-cache pulls, P3 in-flight run, P5 observability, P6 asset) | Medium | stop and report; never `--manual`; follow the runbook re-fire only on operator direction |
| jq change corrupts the tick record | Low | T19 arity pin + S8 sentinel row + the shipper's own T4 positive control |
| Replace leaves the registry dark | Low | volume preserved; runbook `apply-failed`/`unverified` recovery (`recovery-read` block); running web containers keep serving |
| 7341 cannot PASS within the verification window | Certain (24 h boot-scoped span) | disclosed in Research Reconciliation and Phase 5; not forced |
| Func-keyed rows crowd the HTTP half (8-slot sub-quota) | Low | 7556 grades on presence of any deadline 5xx; >= 4 pairs per tick survive; accounted via `exempt_cap` |
| `${`/`%{` in a new comment breaks templatefile | Low | explicit rule above; the suite's render step and `infra-validation` catch it |

## Sharp Edges

- The `## User-Brand Impact` section above is filled (threshold `aggregate pattern`); an empty or filler
  section would fail deepen-plan Phase 4.6.
- The 9353 probe extracts `is_cap_exempt`'s body with an awk that stops at the first line that is exactly a
  closing brace; do not introduce a lone `}` line inside the function.
- Do not put the func test in the call site only: the probe and the issue's closing criterion read the function body.
- Local `node_modules` is stale: never "fix" a local vitest failure by touching the lockfile in this PR.
- T9's old assertion `grep -qF 'PatchBlobUpload'` also matches the heartbeat echo; any replacement must key on a substring
  only the shipped func-keyed row carries.

## References

- Issue #9373; probe PR #9353; probe issues #7556/#7555; shipper origin #7440/#7444/#7455; sub-quota #7555.
- `apps/web-platform/infra/cloud-init-registry.yml` (shipper heredoc), `apps/web-platform/infra/zot-log-shipper.test.sh`
- `scripts/followthroughs/zot-shipper-exempt-func-9353.sh`, `zot-log-channel-7440.sh`, `zot-fill-rate-7341.sh`, `zot-upload-ceiling-7556.sh`
- ADR-184 (shipper), ADR-190 (deadlines; real error shapes), ADR-096/ADR-169 (registry host replace)
- `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`, `betterstack-log-query.md`
- `scripts/registry-replace-preflight.sh`, `apps/web-platform/infra/registry-userdata-budget.sh`,
  `plugins/soleur/test/cloud-init-user-data-size.test.ts`
