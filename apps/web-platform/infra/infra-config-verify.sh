#!/usr/bin/env bash
set -euo pipefail

# #7104 PR-B — WHICH PASS IS THIS?
#
# The same artifact runs twice: once to sense, and once after the bounded re-push to
# render the terminal verdict. Running the SAME tested file twice is the whole reason
# the body was extracted from the workflow (plan R22.2) — the alternative was 240
# duplicated lines of untestable YAML across two steps.
#
#   pass 1  senses. On the ONE recoverable shape — a push was expected and the host's
#           frame predates this apply — it SOFT-FAILS: emits verdict=pending plus the
#           observed start_ts and exits 0, handing off to the re-push steps. Every
#           other failure still exits non-zero exactly as before.
#   pass 2  renders the terminal verdict and fails closed. It never soft-fails, because
#           there is no third push: boundedness is structural (a step cannot run twice
#           in a job), not a latch.
#
# Pass 1's soft-fail is the one new failure mode the split introduces, and it is the
# catastrophic one if it goes wrong: a job that greens having verified nothing, which
# is #6594's latched false-green reintroduced by its own remedy. Two things contain it
# — the terminal-verdict backstop step (`if: always()`), and Guard 1 pinning every
# consumer `if:` literal against the strings this file can actually emit.
VERIFY_PASS="${VERIFY_PASS:-1}"
if [[ ! "$VERIFY_PASS" =~ ^(1|2)$ ]]; then
  echo "::error::VERIFY_PASS is '${VERIFY_PASS}', not 1 or 2. Refusing to guess which verification semantic applies — pass 1 may defer to a re-push, pass 2 may not, and picking either by accident is how a gate greens without adjudicating." >&2
  exit 1
fi

# #7104 PR-B review — DEFAULT IT HERE, at the top, with every other input.
#
# This was the one variable in the file read bare (`"$ALLOW_MISSING_STATUS"`, ~line 145) with no
# `:-` default under `set -u`. Both production callers happen to set it, so the gap is invisible
# in CI — but a direct invocation (the documented inner loop while editing this script, and what
# the suite's own harness does) aborts with `ALLOW_MISSING_STATUS: unbound variable` at the final
# adjudication, AFTER the polling has already run. Defaulting to the safe value here also makes
# the safe value explicit rather than incidental: 404-tolerance is opt-in.
ALLOW_MISSING_STATUS="${ALLOW_MISSING_STATUS:-false}"

APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE --plain 2>/dev/null || echo "soleur.ai")
WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET --plain)
CF_ACCESS_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain 2>/dev/null || doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain)
CF_ACCESS_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET --plain 2>/dev/null || doppler secrets get CI_SSH_ACCESS_TOKEN_SECRET --plain)

# Initial delay: the async script + state write + sync + restart
# scheduling takes ~5-8s; polling immediately wastes attempt 1.
sleep 8

# The webhook returns HTTP 202 the moment the hook TRIGGERS, not when
# the async handler finishes writing files (trigger-and-forget,
# #4804). So success is NOT "the proxy responded" — it is "the state
# JSON proves every file landed". Assert the full invariant:
#   exit_code == 0 AND files_failed == 0 AND files_written == files_total
#                 AND files_total == EXPECTED (repo FILE_MAP length)
#
# #6178 false-green fix: the prior gate compared files_written vs the
# JSON's OWN files_total, which passes on a STALE status from an older,
# smaller FILE_MAP (a webhook restart-race left the host at 13/13 clean
# while the repo FILE_MAP was 15 — the gate went green while the 2
# cutover probe scripts were NEVER delivered). Derive the EXPECTED count
# from the repo's infra-config-apply.sh FILE_MAP at verify time: this
# still auto-tracks future FILE_MAP additions (not hardcoded) AND now
# catches UNDER-delivery (a host that landed fewer files than the repo
# expects). handler_bootstrap runs before this push and updates the host
# handler to the current FILE_MAP, so the count is aligned on a healthy
# apply.
# #6594 (PR-B): the adjudication logic lives in a sourceable, TESTED script
# (infra-config-gate.sh; infra-config-gate.test.sh drives it). CWD is INFRA_DIR.
# shellcheck source=/dev/null
source ./infra-config-gate.sh
# #7104 task 6.11 — anti-vacuity, mirroring the existing `declare -F infra_config_red_alert`
# pattern. If the source above ever stops providing the predicate (a rename, a partial
# revert, a merge that drops the function), `infra_config_should_repush` would be an
# unbound command. Under `set -e` that aborts the step, which is safe — but it aborts it
# with `command not found`, mid-poll, looking like an infrastructure fault rather than a
# missing safety contract. Fail here instead, before any polling, naming the actual cause.
if ! declare -F infra_config_should_repush >/dev/null; then
  echo "::error::infra_config_should_repush is not defined after sourcing infra-config-gate.sh — the predicate that authorises the bounded re-push is missing, so this gate cannot distinguish the recoverable shape from an unrecoverable one. Failing closed."
  exit 1
fi
# `|| true`: infra_config_expected_count ends in `grep -c`, which exits 1 on
# zero matches. Without this, a zero-row FILE_MAP would abort the step here
# under `set -eo pipefail` BEFORE the numeric guard below can emit its
# diagnostic (review, code-quality P-low). The guard still fails closed —
# an empty EXPECTED_COUNT trips the regex check.
# #7104 PR-B — THE RESPONSE PATH IS INJECTABLE, and the default is the FIXED path on purpose.
#
# This body used to hardcode "$STATUS_RESPONSE" at 20 sites. That was safe
# while it was a `run:` block executing once per job, and became unsafe the moment the verbatim
# extraction made it an artifact a suite drives six times per run: the AC17 cases drive the REAL
# script, so two concurrent drives clobber each other's frame. Measured by three independent
# reviewers — 6 concurrent runs produced 5 red, and the mutation battery then aborts on its own
# mandatory green baseline, killing all 17 rows. The verbatim move is what imported the
# single-run assumption; byte-identity proved behavioural identity and carried that with it.
#
# The default MUST stay the fixed literal. `Alert on a red infra-config gate (#7220)` is a
# DIFFERENT STEP in a different process and reads the frame back from that exact path to build
# its diagnosis; a mktemp default would leave it reading nothing on every red run. Only the test
# harness overrides this.
STATUS_RESPONSE="${INFRA_CONFIG_STATUS_RESPONSE:-/tmp/infra-config-status-response.txt}"
EXPECTED_COUNT=$(infra_config_expected_count infra-config-apply.sh || true)
if [[ ! "$EXPECTED_COUNT" =~ ^[0-9]+$ || "$EXPECTED_COUNT" -eq 0 ]]; then
  echo "::error::Could not derive EXPECTED FILE_MAP count from infra-config-apply.sh (got '$EXPECTED_COUNT')."
  exit 1
fi
echo "Expected delivered-file count (repo FILE_MAP): $EXPECTED_COUNT"
EXIT_CODE=""
FILES_FAILED=""
FILES_WRITTEN=""
FILES_TOTAL=""
for attempt in 1 2 3; do
  # Truncate per attempt. `curl -s -o` leaves the PRIOR body in place on a transport
  # failure, so without this a 000 on the last attempt leaves an EARLIER attempt's
  # valid 200 frame on disk — and the red-gate alert step below reads that same path
  # and `jq -e .`s it, so it would classify a dead listener as "reachable, activation
  # failure" and tell the operator app health is unaffected. The pre-apply poller has
  # done this since it was written; this is the sibling that was missed.
  : > "$STATUS_RESPONSE"
  HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
  HTTP_CODE=$(curl -s -o "$STATUS_RESPONSE" -w '%{http_code}' \
    --max-time 10 \
    -H "X-Signature-256: sha256=${HMAC}" \
    -H "CF-Access-Client-Id: ${CF_ACCESS_ID}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}" \
    "https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    EXIT_CODE=$(jq -r '.exit_code' "$STATUS_RESPONSE" 2>/dev/null || echo "MISSING")
    FILES_FAILED=$(jq -r '.files_failed' "$STATUS_RESPONSE" 2>/dev/null || echo "MISSING")
    FILES_WRITTEN=$(jq -r '.files_written' "$STATUS_RESPONSE" 2>/dev/null || echo "MISSING")
    FILES_TOTAL=$(jq -r '.files_total' "$STATUS_RESPONSE" 2>/dev/null || echo "MISSING")
    # Poll fast-path: stop polling once the COUNT invariant holds (single-
    # sourced in infra-config-gate.sh). The CONTENT assert is deliberately NOT
    # here — it runs once after the loop (terminal). Asserting content inside
    # the loop would retry across fresh connector selections = any-of-3 (#6594).
    if infra_config_count_invariant "$STATUS_RESPONSE" infra-config-apply.sh; then
      echo "Infra-config apply count invariant holds (exit_code=0, files_written=${FILES_WRITTEN}/${FILES_TOTAL}, expected=${EXPECTED_COUNT}, files_failed=0 on attempt $attempt); running terminal adjudication."
      cat "$STATUS_RESPONSE"
      break
    fi
    echo "Attempt $attempt: exit_code=$EXIT_CODE files_failed=$FILES_FAILED files_written=$FILES_WRITTEN files_total=$FILES_TOTAL expected=$EXPECTED_COUNT (retrying in 5s...)"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    echo "Attempt $attempt: infra-config-status endpoint not found (HTTP 404)"
  else
    echo "Attempt $attempt: HTTP $HTTP_CODE (retrying in 5s...)"
  fi

  if [[ "$attempt" -lt 3 ]]; then
    sleep 5
  fi
done

# --- Final adjudication (fail loud; no silent pass) ---
if [[ "$HTTP_CODE" == "404" ]]; then
  if [[ "$ALLOW_MISSING_STATUS" == "true" ]]; then
    echo "::warning::infra-config-status returned 404; tolerated via allow_missing_status_endpoint (documented first-bootstrap escape hatch). NOTHING was adjudicated on this run — no count invariant, no content assert, no freshness assertion."
    # Write the output on this path too. It is the WEAKEST evidence the whole design
    # can exit green on, and leaving it unwritten made it indistinguishable from
    # `verified` to every consumer — absence reading as good news.
    echo "freshness_evidence=none" >> "$GITHUB_OUTPUT"
    # #7104 PR-B review — AND THE VERDICT MUST SAY SO TOO.
    #
    # This arm did not exit. It fell through to the tail `verdict=verified`, so the one path in
    # the whole design that adjudicates NOTHING was emitting the same terminal verdict as a full
    # count-plus-content-plus-freshness pass. The `freshness_evidence=none` output above was
    # added to stop absence reading as good news, and the verdict immediately undid it by
    # asserting the strongest possible claim.
    #
    # `unadjudicated` is a distinct terminal state: it is NOT `verified` (nothing was checked)
    # and NOT `pending` (nothing is going to check it — there is no re-push on this path).
    echo "verdict=unadjudicated" >> "$GITHUB_OUTPUT"
    exit 0
  else
    echo "::error::infra-config-status returned HTTP 404 after all retries — the host's hooks.json predates the status endpoint and the apply did NOT verify. This is the false-success freeze vector (#4804). For a genuine first bootstrap, re-run via workflow_dispatch with allow_missing_status_endpoint=true."
    cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
    exit 1
  fi
elif [[ "$HTTP_CODE" == "200" ]]; then
  # Terminal adjudication (OUTSIDE the retry loop, #6594 PR-B): the count
  # invariant (#6178 under-delivery guard) AND the per-file content assert —
  # each delivered file's reported sha256 must equal the repo file the apply
  # ran from (CWD is the checked-out INFRA_DIR at the applied SHA). A content
  # mismatch is terminal and names the diverging file. This is what catches a
  # stale-but-same-count host: 15/15 clean while ci-deploy.sh was never re-
  # delivered (the exact #6594 false-green). Single-sourced in
  # infra-config-gate.sh; driven by infra-config-gate.test.sh.
  if ! adjudicate_infra_config "$STATUS_RESPONSE" . infra-config-apply.sh; then
    cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
    exit 1
  fi
  # #7220 AC20 — FRESHNESS PIN. Everything adjudicated above is satisfiable by a
  # frame the host published on an EARLIER apply: exit_code=0, files_written=19/19,
  # matching per-file digests and a populated restarts[] all persist on disk. So
  # without this the gate proves "some apply reconciled", never "THIS one did" — and
  # a handler that dies before publishing is exactly what leaves the previous frame
  # in place, which is the #7220 shape. Same guard as
  # scripts/followthroughs/ac12-telemetry-positive-control-7103.sh Guard 1.
  FRAME_START_TS=$(jq -r '.start_ts // empty' "$STATUS_RESPONSE" 2>/dev/null || true)
  if [[ ! "$FRAME_START_TS" =~ ^[0-9]+$ ]]; then
    echo "::error::infra-config frame carries no numeric start_ts ('${FRAME_START_TS:-<absent>}') — freshness cannot be established, so a stale frame cannot be distinguished from this apply's. Failing closed."
    cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
    exit 1
  fi
  # #7104 — WHICH freshness assertion applies depends on whether a push was expected.
  # Validated here as well as at the producer: the sensor can only emit "true"/"false",
  # but an unset value means the plan step never recorded one, and defaulting THAT to
  # either arm would pick a verification semantic by accident.
  if [[ ! "${DPF_REPLACED:-}" =~ ^(true|false)$ ]]; then
    echo "::error::DPF_REPLACED is '${DPF_REPLACED:-<unset>}', not true/false — the plan step did not record whether terraform_data.deploy_pipeline_fix would be replaced. The gate cannot choose between 'require a newer frame' and 'require an unchanged frame' without it, and guessing either way silently changes what this gate proves. Failing closed."
    exit 1
  fi

  if [[ "$DPF_REPLACED" == "true" ]]; then
    # A push WAS expected, so the #7220 pin applies unchanged: the frame must postdate
    # this apply. This is the arm the dying-handler shape lives on.
    if [[ ! "${APPLY_START_EPOCH:-}" =~ ^[0-9]+$ ]]; then
      echo "::error::APPLY_START_EPOCH was not recorded by the apply step — the freshness pin cannot run, and silently skipping it would restore the stale-frame blind spot. Failing closed."
      exit 1
    fi
    if [[ "$VERIFY_PASS" == "2" ]]; then
      # PASS 2 — did the bounded re-push actually move the frame?
      #
      # The baseline is the start_ts PASS 1 OBSERVED, handed over as a step output —
      # an argument, not a re-read (task 6.10 / R19.3). That matters for a reason
      # beyond plumbing: both operands are now HOST-clock, so host/runner skew
      # cancels exactly instead of needing the 300 s tolerance the runner-clock
      # comparison carries.
      #
      # And the comparison is STRICTLY GREATER, not `-lt` inverted. An unchanged
      # frame means the re-push delivered nothing, which is the failure this whole
      # PR exists to catch — reading equality as success here would make the
      # recovery self-certifying.
      if [[ ! "${REPUSH_BASELINE_TS:-}" =~ ^[0-9]+$ ]]; then
        echo "::error::REPUSH_BASELINE_TS is '${REPUSH_BASELINE_TS:-<unset>}', not numeric — pass 1's observed start_ts did not reach pass 2, so 'the frame moved' cannot be evaluated. Failing closed rather than falling back to the runner-clock baseline, which would silently change what this pass proves."
        echo "verdict=failed" >> "$GITHUB_OUTPUT"
        exit 1
      fi
      if [[ ! "$FRAME_START_TS" -gt "$REPUSH_BASELINE_TS" ]]; then
        echo "::error::RE-PUSH DID NOT DELIVER: the frame still reads start_ts=${FRAME_START_TS} against the ${REPUSH_BASELINE_TS} observed before the re-push — it did not advance. The bounded recovery is spent (one attempt by construction) and this run is terminally red. Do NOT re-run expecting a different result: -target SELECTS resources, it does not force replacement."
        echo "verdict=failed" >> "$GITHUB_OUTPUT"
        cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
        exit 1
      fi
      # #7104 P0-A — THE ABSOLUTE PIN, WHICH PASS 2 HAD LOST.
      #
      # The relative check above is necessary and NOT sufficient. On origin/main this arm was
      # unconditionally `FRAME_START_TS -lt APPLY_START_EPOCH`; inserting the pass-2 branch in
      # front of it left "the frame advanced" as pass 2's ONLY surviving assertion, and
      # APPLY_START_EPOCH — validated a few lines above — was never read again on this path.
      # Any unrelated advance then certifies the recovery: a queued handler invocation, a
      # concurrent trigger, a host clock that stepped forward. That is #7220's shape, in the
      # TERMINAL verdict of the very PR that exists to close it.
      #
      # This is deliberately not a naive AND with the pass-1 comparison. The relative check is
      # host-clock-to-host-clock so skew cancels exactly; this one crosses clocks, so it carries
      # the same 300 s allowance the runner-clock comparisons already carry
      # (INFRA_CONFIG_CLOCK_SKEW_S, single-sourced in infra-config-gate.sh). Without the
      # tolerance a host whose clock lags the runner would be red-lined for a real delivery.
      #
      # AND THE REFERENCE IS THE RE-PUSH, NOT THE ORIGINAL APPLY, WHEN THE RE-PUSH RECORDED ONE.
      # Bounding the advance only by APPLY_START_EPOCH leaves it unbounded in the direction that
      # matters: pass 2 runs after a whole plan+grade+apply cycle, so a frame published moments
      # after the ORIGINAL apply began cannot have been produced by the re-push, yet it clears an
      # APPLY_START_EPOCH-only pin. REPUSH_START_EPOCH is a runner-side stamp taken by the
      # re-push apply step, so it is not host-selectable.
      #
      # Falling back to APPLY_START_EPOCH when it is absent is a documented degradation, not a
      # silent one: it is strictly weaker but still sound (APPLY_START_EPOCH <= REPUSH_START_EPOCH
      # always), the message names which reference was used, and the reference is published as an
      # output so the choice is visible off-host rather than inferred.
      FRESHNESS_REF_EPOCH="$APPLY_START_EPOCH"
      FRESHNESS_REF_LABEL="this workflow's apply"
      FRESHNESS_REF_DEGRADED=1
      if [[ "${REPUSH_START_EPOCH:-}" =~ ^[0-9]+$ ]] && [[ "$REPUSH_START_EPOCH" -ge "$APPLY_START_EPOCH" ]]; then
        FRESHNESS_REF_EPOCH="$REPUSH_START_EPOCH"
        FRESHNESS_REF_LABEL="the bounded re-push"
        FRESHNESS_REF_DEGRADED=0
      fi
      echo "freshness_reference=${FRESHNESS_REF_EPOCH}" >> "$GITHUB_OUTPUT"
      # "NOT A SILENT ONE" WAS NOT TRUE (#7546 review). The comment above justified the fallback
      # on two grounds and neither held: the message naming the reference is printed only on the
      # SUCCESS path, as an un-annotated stdout line inside a GREEN run -- which this repo's own
      # prose repeatedly calls "a log line in a run nobody opens" -- and `freshness_reference` is
      # published but has ZERO consumers, while APPLY_START_EPOCH is never published at all, so
      # nothing off-host can tell a degraded reference from a pinned one. Worse, the arm below
      # emits `freshness_evidence=verified` identically either way, and that verdict re-arms the
      # container swap and two issue-closing steps.
      #
      # Measured: deleting the producer of repush_start_epoch flipped a STALE FRAME AFTER RE-PUSH
      # error into `verdict=verified` with byte-identical evidence. So say it out loud, and route
      # it to the degraded-freshness reporter that already exists for exactly this class.
      if [[ "$FRESHNESS_REF_DEGRADED" -eq 1 ]]; then
        echo "::warning::The pass-2 freshness pin DEGRADED to this workflow's apply start (${APPLY_START_EPOCH}) because the bounded re-push published no usable start epoch (REPUSH_START_EPOCH='${REPUSH_START_EPOCH:-<absent>}'). That reference is strictly weaker: a frame published moments after the ORIGINAL apply began cannot have been produced by the re-push, yet it clears an APPLY_START_EPOCH-only pin. This run's verdict rests on the weaker test."
      fi
      # UPPER BOUND, NOT JUST A LOWER ONE (#7546 review). `start_ts` is published BY THE HOST and
      # is therefore host-selectable, and this arm bounded it only from below -- so a frame dated
      # in the future verified. Measured: start_ts=9999999999 (year 2286) returned rc=0
      # verdict=verified "Re-push VERIFIED". The `future_frame` guard already exists and is
      # already reasoned about correctly in infra-config-gate.sh ("a host-clock anomaly or a
      # fabricated frame, so it fails closed on BOTH sub-arms") -- but it lives inside
      # infra_config_frame_stability, which this file calls ONLY on the DPF_REPLACED=false arm.
      # Pass 2 is a fresh verdict path certifying a SECOND production write as recovered and it
      # inherited none of it. A forward host-clock step defeats both of this arm's comparisons
      # at once, and the stale-frame error two lines down names "a host clock step" as a threat
      # it detects -- in one direction only.
      PASS2_NOW_EPOCH=$(date -u +%s)
      if [[ "$FRAME_START_TS" -gt $((PASS2_NOW_EPOCH + INFRA_CONFIG_CLOCK_SKEW_S)) ]]; then
        echo "::error::FRAME FROM THE FUTURE AFTER RE-PUSH: the status endpoint reports an apply that started at ${FRAME_START_TS}, which is more than the ${INFRA_CONFIG_CLOCK_SKEW_S}s skew allowance ahead of this runner's clock (now=${PASS2_NOW_EPOCH}, delta=$((FRAME_START_TS - PASS2_NOW_EPOCH))s). start_ts is published by the host, so this is a host-clock anomaly or a fabricated frame — not a delivery this gate can vouch for. The bounded recovery is spent and this run has no verified delivery."
        echo "verdict=failed" >> "$GITHUB_OUTPUT"
        cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
        exit 1
      fi
      if [[ "$FRAME_START_TS" -lt $((FRESHNESS_REF_EPOCH - INFRA_CONFIG_CLOCK_SKEW_S)) ]]; then
        echo "::error::STALE FRAME AFTER RE-PUSH: the frame DID advance (${REPUSH_BASELINE_TS} -> ${FRAME_START_TS}), but it still predates ${FRESHNESS_REF_LABEL} (began ${FRESHNESS_REF_EPOCH}) by $((FRESHNESS_REF_EPOCH - FRAME_START_TS))s, which is beyond the ${INFRA_CONFIG_CLOCK_SKEW_S}s host/runner clock allowance. So something moved the frame, but it was not this re-push — a queued handler invocation, a concurrent trigger, or a host clock step. The delivery this run needed is still unproven and the bounded recovery is spent. This is a DIFFERENT diagnosis from 'the frame did not move' and it has a different lever: do not re-run, and do not read the advance as a delivery. Inspect the host's journal for which invocation published start_ts=${FRAME_START_TS}."
        echo "verdict=failed" >> "$GITHUB_OUTPUT"
        cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
        exit 1
      fi
      echo "Re-push VERIFIED: frame advanced ${REPUSH_BASELINE_TS} -> ${FRAME_START_TS} (host clock, both operands) and postdates ${FRESHNESS_REF_LABEL} (${FRESHNESS_REF_EPOCH}) within the ${INFRA_CONFIG_CLOCK_SKEW_S}s allowance."
      # `degraded`, not `verified`, when the pin fell back -- so the existing
      # `Report degraded freshness evidence` step fires and the weaker test leaves an off-host
      # record instead of being indistinguishable from a fully-pinned pass.
      if [[ "$FRESHNESS_REF_DEGRADED" -eq 1 ]]; then
        echo "freshness_evidence=degraded" >> "$GITHUB_OUTPUT"
      else
        echo "freshness_evidence=verified" >> "$GITHUB_OUTPUT"
      fi
    # NO SKEW ALLOWANCE HERE, AND THAT ASYMMETRY IS DELIBERATE (#7546 review).
    #
    # Pass 2 tolerates INFRA_CONFIG_CLOCK_SKEW_S on its staleness test; this one does not, and
    # review flagged the difference. Symmetrising it would be the WRONG fix, in the dangerous
    # direction: pass 1 is asking "did this apply deliver?", so tolerating 300s of "before"
    # accepts a frame published BEFORE the apply started as proof that the apply landed --
    # a false `verdict=verified`, which re-arms the container swap and closes the founder's
    # drift issues. Pass 2 is asking a narrower question ("did the RE-PUSH move the frame?")
    # where the operands are a runner stamp and a host stamp and the tolerance buys a real
    # false-red reduction.
    #
    # The cost of the strictness here is bounded and much smaller: a host clock lagging the
    # runner can classify a genuine delivery as stale and trigger the bounded re-push -- a
    # production write on a healthy channel. Measured skew for this fleet is ~1-2s against a
    # +/-2s resolution floor (plan Task 2.1, which is why R2 was NOT shipped), so the window in
    # which that can happen is a frame published within ~2s of the apply's own start.
    #
    # Do not "fix" this by adding the allowance. If the spurious-re-push path is ever measured
    # in the wild, the correct move is to compare host-clock operands on BOTH sides, not to
    # widen the acceptance window on the pass that decides whether the config is live.
    elif [[ "$FRAME_START_TS" -lt "$APPLY_START_EPOCH" ]]; then
      # PASS 1, stale frame — the documented webhook-restart race, or something else
      # entirely. The predicate decides which, and it is the ONLY thing that may
      # authorise a production write: allow-list semantics, so anything it cannot
      # classify falls through to the terminal error below rather than to a re-push.
      if infra_config_should_repush "$STATUS_RESPONSE" "$DPF_REPLACED" "$APPLY_START_EPOCH"; then
        echo "::warning::STALE FRAME at ${FRAME_START_TS} (apply began ${APPLY_START_EPOCH}) — this matches the documented webhook-restart race. Deferring the verdict to a single bounded re-push; pass 2 renders the terminal result and fails closed."
        # These three outputs ARE the handoff. Written before anything that can exit,
        # and the run is only safe because the always() backstop step fails the job if
        # no pass ever renders a terminal verdict.
        echo "verdict=pending" >> "$GITHUB_OUTPUT"
        echo "repush_needed=true" >> "$GITHUB_OUTPUT"
        echo "observed_start_ts=${FRAME_START_TS}" >> "$GITHUB_OUTPUT"
        exit 0
      fi
      echo "::error::STALE FRAME: the status endpoint reports an apply that started at ${FRAME_START_TS}, BEFORE this workflow's apply began at ${APPLY_START_EPOCH}. The handler did not publish a new frame for this run — every green value above belongs to a previous apply. This is the #7220 failure shape: delivery reported against a frame the dying handler never overwrote."
      echo "verdict=failed" >> "$GITHUB_OUTPUT"
      cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
      exit 1
    else
      echo "Frame freshness OK: start_ts=${FRAME_START_TS} postdates this apply's start (${APPLY_START_EPOCH})."
      echo "freshness_evidence=verified" >> "$GITHUB_OUTPUT"
    fi
  else
    # NO push was expected, so no new frame should exist. Requiring a newer frame here
    # is what reds a correct run (measured: run 31636951749, 2026-08-12). Assert the
    # frame is UNCHANGED instead. Verdict logic is in infra-config-gate.sh so it is
    # driven by infra-config-gate.test.sh rather than living only in this YAML.
    # `|| STABILITY_RC=$?` is the sanctioned capture form (AP-022,
    # scripts/lint-workflow-errexit-capture.py). The obvious
    # `X=$(cmd); rc=$?` is an ABORT rather than a capture: `run:` bodies execute as
    # `bash -e {0}`, so a non-zero adjudication would kill the step ON THE ASSIGNMENT
    # and every branch below — including the ::error:: that explains why — would never
    # run. The step would still fail closed, but it would fail mute.
    STABILITY_RC=0
    NOW_EPOCH=$(date -u +%s)
    STABILITY=$(infra_config_frame_stability "$FRAME_START_TS" "${PRE_APPLY_FRAME_START_TS:-}" "${PRE_FRAME_STATUS:-}" "$NOW_EPOCH" "${APPLY_START_EPOCH:-}") || STABILITY_RC=$?
    if [[ "$STABILITY_RC" -ne 0 ]]; then
      # Publish the verdict for the red-gate alert. Without it that step re-derives a
      # diagnosis from the frame, and for these three verdicts the frame looks HEALTHY
      # (200, parses, fatal_line=0), so it lands in the "no fatal attribution" arm and
      # tells the operator this is a cosmetic ACTIVATION failure with app health
      # unaffected — while handing them a Better Stack query that returns nothing
      # because no fatal occurred. For `unexpected_push` every clause of that is false.
      echo "stability_verdict=${STABILITY}" >> "$GITHUB_OUTPUT"
      case "$STABILITY" in
        future_frame)
          echo "::error::FRAME FROM THE FUTURE: the status endpoint reports an apply that started at ${FRAME_START_TS}, which is more than the 300s skew allowance ahead of this runner's clock (now=${NOW_EPOCH}, delta=$((FRAME_START_TS - NOW_EPOCH))s). On a run that pushed nothing, that is a host-clock anomaly or a fabricated frame — not a delivery this gate can vouch for."
          ;;
        unexpected_push)
          echo "::error::UNEXPECTED PUSH: this run's plan did not replace terraform_data.deploy_pipeline_fix, so no config push should have fired — but the status frame moved forward (pre=${PRE_APPLY_FRAME_START_TS}, post=${FRAME_START_TS}). Either the applied plan diverged from the graded one, or something other than this workflow wrote to the host's sole credential channel. Both are terminal."
          ;;
        frame_regressed)
          echo "::error::FRAME WENT BACKWARDS: the status frame reports an EARLIER start (pre=${PRE_APPLY_FRAME_START_TS}, post=${FRAME_START_TS}) than it did before this apply. That is a state rollback or a host clock jump on a host that cannot be re-provisioned."
          ;;
        *)
          echo "::error::Frame-stability adjudication failed (verdict='${STABILITY}'). Failing closed."
          ;;
      esac
      cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
      exit 1
    fi

    if [[ "$STABILITY" == "stable" ]]; then
      echo "::notice::No config push was expected on this run (deploy_pipeline_fix was not replaced), so no new status frame should exist. VERIFIED: the frame is unchanged across this apply (start_ts=${FRAME_START_TS}, identical to the pre-apply reading) and its start_ts is not in the future. This establishes that the delivery channel answered and that NO NEW STATUS FRAME WAS PUBLISHED across this apply. Stated that narrowly on purpose: it does NOT prove nothing was written to the host (a seccomp or apparmor merge writes to the host while the frame correctly does not move), and it does NOT re-verify the bytes currently on disk — the frame records the last write, not a fresh read. The per-file digest match is NOT listed as evidence here: deploy_pipeline_fix was not replaced precisely because none of its hashed files changed, so on this arm a content match is guaranteed by construction and proves nothing."
      echo "freshness_evidence=verified" >> "$GITHUB_OUTPUT"
    elif [[ "$STABILITY" != "degraded:"* ]]; then
      # FAIL CLOSED on an unrecognised verdict. This arm exists because the previous
      # shape was a bare `else`: any token the adjudicator returns with rc 0 that is
      # not literally "stable" landed in the PASSING branch below. The failing side of
      # this dispatch already had a fail-closed default; the passing side did not, so
      # adding one `case` arm to infra_config_frame_stability was enough to create a
      # brand-new exit-0 path with no edit to this file at all.
      echo "::error::Frame-stability returned an unrecognised verdict '${STABILITY}'. A verdict this gate cannot interpret must never be treated as a pass. Failing closed."
      cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
      exit 1
    else
      # degraded:<measured-status>. Pass, but say exactly what was and was not shown —
      # and escalate out of band, because a ::warning:: in a green run is a log line
      # nobody reads (the same criticism #7220 AC17 levelled at ::error:: annotations).
      PRE_WHY="${STABILITY#degraded:}"
      case "$PRE_WHY" in
        unreachable) PRE_DETAIL="the reading taken BEFORE the apply got no response (3 attempts over ~15s). Two readings are consistent with that and this run cannot distinguish them: a transient network blip, OR something restarted or reconfigured the listener outside this workflow — note the apply changed nothing on the host, so a listener that was down before and up after is not explained by this run" ;;
        http404)     PRE_DETAIL="the pre-apply reading returned HTTP 404 (no status endpoint) while the post-apply reading returned 200. On a run that pushed nothing the endpoint should not have appeared — treat this as a host changed outside this workflow, or a transient edge 404" ;;
        malformed)   PRE_DETAIL="the pre-apply reading returned HTTP 200 but carried no numeric start_ts" ;;
        secret_unavailable) PRE_DETAIL="the pre-apply reading never fired because WEBHOOK_DEPLOY_SECRET could not be read from Doppler — the step DID run and DID record that. A prd credential read failing on the workflow that delivers /etc/default/soleur-doppler-token is its own incident, separate from a missing reading" ;;
        *)           PRE_DETAIL="the pre-apply reading step did not record a result at all (the step did not run, or its result did not reach this step)" ;;
      esac
      echo "::warning::Freshness evidence is DEGRADED on this run. No config push was expected (deploy_pipeline_fix was not replaced) and the status endpoint answered 200 after the apply — but ${PRE_DETAIL}, so this run cannot show the frame was unchanged. VERIFIED: the endpoint answered, the frame parses, its start_ts is not in the future, and no frame postdating this apply was published. NOT VERIFIED: that the frame is byte-identical to the one that preceded this apply. (The per-file digest match is omitted from the VERIFIED list deliberately — on a no-push arm it is guaranteed by construction and is not independent evidence.) The delivery channel is reachable now; this run is recorded in Sentry as op=infra-config-preframe-degraded."
      echo "freshness_evidence=degraded" >> "$GITHUB_OUTPUT"
      echo "preframe_status=${PRE_WHY}" >> "$GITHUB_OUTPUT"
    fi
  fi
  echo "Infra-config apply verified: count invariant + per-file content match (#6594 PR-B)."
elif [[ "$HTTP_CODE" == "000" || "$HTTP_CODE" == "502" || "$HTTP_CODE" == "503" ]]; then
  # #7095 R34 — DISTINCT from the 404 branch above, and the distinction is the whole
  # point. 404 means "the endpoint is not there" (a genuinely old hooks.json), and its
  # message correctly points at first-bootstrap. 000/502/503 mean the webhook LISTENER
  # ITSELF IS DOWN — the status endpoint dies WITH the unit, so a bricked webhook
  # produced the 404 message before this branch existed: it pointed the engineer at
  # first-bootstrap, and its suggested allow_missing_status_endpoint=true flag would
  # have SUPPRESSED the very failure. Naming this shape separately is what stops a
  # bricked remediation channel reading as a stale-host cosmetic.
  echo "::error::infra-config-status is UNREACHABLE (HTTP $HTTP_CODE) after 3 attempts — this is the webhook listener being DOWN, not a missing endpoint. Do NOT re-run with allow_missing_status_endpoint=true: that flag suppresses exactly this failure."
  echo "::error::RECOVERY — the bounded automatic re-push added by #7104 does NOT cover this shape: it fires only on a stale FRAME from a live listener, and this branch means the listener itself is DOWN, so there is nothing to re-push through. A plain workflow_dispatch re-run does NOT fix it either. -target SELECTS resources, it does not force replacement, and this branch fires after a SUCCESSFUL apply, so the provisioners are clean and their remote-exec never re-runs. The route back is an explicit replace: (run from apps/web-platform/infra) doppler run --name-transformer tf-var -- terraform apply -replace=terraform_data.infra_config_handler_bootstrap -target=terraform_data.infra_config_handler_bootstrap -input=false -lock-timeout=120s (root SSH over the CF Tunnel, which does not depend on the webhook being alive), or a nonce bump in push-infra-config.sh. webhook.service itself is delivered by terraform_data.deploy_pipeline_fix, not by the bridge. The webhook is the ONLY no-SSH remediation channel on this host and the host cannot be replaced (cx33, orderable in 0 of 3 EU DCs), so treat a persistent unreachable state as a P1."
  cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
  exit 1
else
  echo "::error::infra-config-status did not respond with HTTP 200 after 3 attempts (last HTTP $HTTP_CODE). The handler is async behind a 202 trigger-and-forget, so a non-responding status endpoint cannot be treated as success."
  cat "$STATUS_RESPONSE" >&2 2>/dev/null || true
  exit 1
fi

# Terminal verdict. Reached only on a path that did NOT exit: the fresh-frame arm, the
# unchanged-frame arm (DPF_REPLACED=false), the 404 escape hatch, and pass 2's verified
# arm. Pass 1's soft-fail exits 0 above having already written verdict=pending, so it
# never reaches here.
#
# Emitted at the tail rather than inside each branch for a specific reason: AC20 licenses
# citing production run 31714143720 as task 10.4's evidence, and it does so only while the
# DPF_REPLACED == "false" branch is unchanged by this PR. Writing the verdict inside that
# branch would have invalidated the one piece of production evidence PR-B has.
echo "verdict=verified" >> "$GITHUB_OUTPUT"
