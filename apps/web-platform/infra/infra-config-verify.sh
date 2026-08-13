#!/usr/bin/env bash
set -euo pipefail
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
# `|| true`: infra_config_expected_count ends in `grep -c`, which exits 1 on
# zero matches. Without this, a zero-row FILE_MAP would abort the step here
# under `set -eo pipefail` BEFORE the numeric guard below can emit its
# diagnostic (review, code-quality P-low). The guard still fails closed —
# an empty EXPECTED_COUNT trips the regex check.
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
  : > /tmp/infra-config-status-response.txt
  HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
  HTTP_CODE=$(curl -s -o /tmp/infra-config-status-response.txt -w '%{http_code}' \
    --max-time 10 \
    -H "X-Signature-256: sha256=${HMAC}" \
    -H "CF-Access-Client-Id: ${CF_ACCESS_ID}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}" \
    "https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    EXIT_CODE=$(jq -r '.exit_code' /tmp/infra-config-status-response.txt 2>/dev/null || echo "MISSING")
    FILES_FAILED=$(jq -r '.files_failed' /tmp/infra-config-status-response.txt 2>/dev/null || echo "MISSING")
    FILES_WRITTEN=$(jq -r '.files_written' /tmp/infra-config-status-response.txt 2>/dev/null || echo "MISSING")
    FILES_TOTAL=$(jq -r '.files_total' /tmp/infra-config-status-response.txt 2>/dev/null || echo "MISSING")
    # Poll fast-path: stop polling once the COUNT invariant holds (single-
    # sourced in infra-config-gate.sh). The CONTENT assert is deliberately NOT
    # here — it runs once after the loop (terminal). Asserting content inside
    # the loop would retry across fresh connector selections = any-of-3 (#6594).
    if infra_config_count_invariant /tmp/infra-config-status-response.txt infra-config-apply.sh; then
      echo "Infra-config apply count invariant holds (exit_code=0, files_written=${FILES_WRITTEN}/${FILES_TOTAL}, expected=${EXPECTED_COUNT}, files_failed=0 on attempt $attempt); running terminal adjudication."
      cat /tmp/infra-config-status-response.txt
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
  else
    echo "::error::infra-config-status returned HTTP 404 after all retries — the host's hooks.json predates the status endpoint and the apply did NOT verify. This is the false-success freeze vector (#4804). For a genuine first bootstrap, re-run via workflow_dispatch with allow_missing_status_endpoint=true."
    cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
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
  if ! adjudicate_infra_config /tmp/infra-config-status-response.txt . infra-config-apply.sh; then
    cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
    exit 1
  fi
  # #7220 AC20 — FRESHNESS PIN. Everything adjudicated above is satisfiable by a
  # frame the host published on an EARLIER apply: exit_code=0, files_written=19/19,
  # matching per-file digests and a populated restarts[] all persist on disk. So
  # without this the gate proves "some apply reconciled", never "THIS one did" — and
  # a handler that dies before publishing is exactly what leaves the previous frame
  # in place, which is the #7220 shape. Same guard as
  # scripts/followthroughs/ac12-telemetry-positive-control-7103.sh Guard 1.
  FRAME_START_TS=$(jq -r '.start_ts // empty' /tmp/infra-config-status-response.txt 2>/dev/null || true)
  if [[ ! "$FRAME_START_TS" =~ ^[0-9]+$ ]]; then
    echo "::error::infra-config frame carries no numeric start_ts ('${FRAME_START_TS:-<absent>}') — freshness cannot be established, so a stale frame cannot be distinguished from this apply's. Failing closed."
    cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
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
    if [[ "$FRAME_START_TS" -lt "$APPLY_START_EPOCH" ]]; then
      echo "::error::STALE FRAME: the status endpoint reports an apply that started at ${FRAME_START_TS}, BEFORE this workflow's apply began at ${APPLY_START_EPOCH}. The handler did not publish a new frame for this run — every green value above belongs to a previous apply. This is the #7220 failure shape: delivery reported against a frame the dying handler never overwrote."
      cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
      exit 1
    fi
    echo "Frame freshness OK: start_ts=${FRAME_START_TS} postdates this apply's start (${APPLY_START_EPOCH})."
    echo "freshness_evidence=verified" >> "$GITHUB_OUTPUT"
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
      cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
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
      cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
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
  echo "::error::RECOVERY — a plain workflow_dispatch re-run does NOT fix this. -target SELECTS resources, it does not force replacement, and this branch fires after a SUCCESSFUL apply, so the provisioners are clean and their remote-exec never re-runs. The route back is an explicit replace: terraform apply -replace=terraform_data.infra_config_handler_bootstrap (root SSH over the CF Tunnel, which does not depend on the webhook being alive), or a nonce bump in push-infra-config.sh. webhook.service itself is delivered by terraform_data.deploy_pipeline_fix, not by the bridge. The webhook is the ONLY no-SSH remediation channel on this host and the host cannot be replaced (cx33, orderable in 0 of 3 EU DCs), so treat a persistent unreachable state as a P1."
  cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
  exit 1
else
  echo "::error::infra-config-status did not respond with HTTP 200 after 3 attempts (last HTTP $HTTP_CODE). The handler is async behind a 202 trigger-and-forget, so a non-responding status endpoint cannot be treated as success."
  cat /tmp/infra-config-status-response.txt >&2 2>/dev/null || true
  exit 1
fi
