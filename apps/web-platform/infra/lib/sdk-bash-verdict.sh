#!/usr/bin/env bash
# sdk-bash-verdict.sh: the ONE mapping from "what `docker exec` of infra/lib/sdk-bash-probe.mjs returned" to a verdict.
# shellcheck disable=SC2034  # SBV_VERDICT / SBV_REASON / SBV_COVERAGE are the function's output contract, read by the sourcing script
# SOURCED, never executed, by two callers that must agree on it (ADR-079 addendum 2026-10-20, CTO ruling):
#   - ci-deploy.sh run_sdk_bash_smoke   (deploy-time smoke, CANARY container, non-blocking)
#   - web-bash-synthetic.sh             (runtime synthetic, RUNNING container, per-host dead-man heartbeat)
# Two copies of the rc 124 / SDK_BASH_DISPATCHED mapping drift; this is the single definition.
#
#   sdk_bash_map_result <exec_rc> <out> <docker_err> <host_timeout_secs>
#     exec_rc            the rc of the `timeout <N> docker exec ... node sdk-bash-probe.mjs`
#     out                the probe's captured stdout (SDK_BASH_DISPATCHED, SDK_BASH_RESULT {json})
#     docker_err         docker's first scrubbed stderr line, or empty
#     host_timeout_secs  the host `timeout` value, only named in the reason
#   Sets (globals, NOT stdout: a subshell would discard them) SBV_VERDICT, SBV_REASON, SBV_COVERAGE.
#     SBV_VERDICT  pass | sdk_bash_smoke_failed | smoke_infra_error
#
# Mapping (the #4941 false-rollback guard; the #10445 shape):
#   rc 0      the probe's own SDK_BASH_RESULT line decides; a `pass` needs coverage sdk_wrapper_shim_prodtuple, and an
#             unparseable or absent result line is smoke_infra_error no_result_line.
#   rc 124    after SDK_BASH_DISPATCHED: sdk_bash_smoke_failed host_timeout_<N>s (Bash hung); before it:
#             smoke_infra_error host_timeout_before_dispatch (a daemon stall or a wedged node start).
#   other rc  after SDK_BASH_DISPATCHED: sdk_bash_smoke_failed probe_rc_<N>_after_dispatch, EXCEPT 137/143 (SIGKILL/SIGTERM:
#             the OOM killer, a container stop or a deploy signal), which are smoke_infra_error probe_killed_rc_<N>.
#             Before it: 125/126/127 are docker_exec_rc_<N>, anything else probe_rc_<N>, all smoke_infra_error.
# The WHOLE LINE `SDK_BASH_DISPATCHED` is matched (a substring in a longer line is not the marker).

sdk_bash_map_result() {
  local exec_rc="${1:-}" out="${2:-}" docker_err="${3:-}" host_timeout="${4:-150}"
  local line json
  SBV_VERDICT=""
  SBV_REASON=""
  SBV_COVERAGE=""
  case "$exec_rc" in
    0)
      line="$(printf '%s\n' "$out" | { grep -a '^SDK_BASH_RESULT ' || true; } | tail -n 1)"
      json="${line#SDK_BASH_RESULT }"
      SBV_VERDICT="$(printf '%s' "$json" | jq -r '.verdict // ""' 2>/dev/null || echo '')"
      SBV_REASON="$(printf '%s' "$json" | jq -r '.reason // ""' 2>/dev/null || echo '')"
      SBV_COVERAGE="$(printf '%s' "$json" | jq -r '.coverage // ""' 2>/dev/null || echo '')"
      [[ "$SBV_COVERAGE" == "sdk_wrapper_shim_prodtuple" || "$SBV_COVERAGE" == "replay_only" ]] || SBV_COVERAGE=""
      case "$SBV_VERDICT" in
        pass)
          # The probe already holds a replay_only pass; refuse one here too (defense in depth): only the
          # shim-and-wrapper tuple may count.
          if [[ "$SBV_COVERAGE" != "sdk_wrapper_shim_prodtuple" ]]; then
            SBV_VERDICT="smoke_infra_error"; SBV_REASON="coverage_replay_only"
          fi ;;
        sdk_bash_smoke_failed|smoke_infra_error) : ;;
        *) SBV_VERDICT="smoke_infra_error"; SBV_REASON="no_result_line${docker_err:+: $docker_err}"; SBV_COVERAGE="" ;;
      esac ;;
    124)
      # `out` still holds whatever the probe printed before `timeout` killed the docker exec client.
      if [[ $'\n'"$out"$'\n' == *$'\nSDK_BASH_DISPATCHED\n'* ]]; then
        SBV_VERDICT="sdk_bash_smoke_failed"; SBV_REASON="host_timeout_${host_timeout}s${docker_err:+: $docker_err}"
      else
        SBV_VERDICT="smoke_infra_error"; SBV_REASON="host_timeout_before_dispatch${docker_err:+: $docker_err}"
      fi ;;
    *)
      # Any other non-zero rc: if the probe had already printed SDK_BASH_DISPATCHED, Bash was handed to the SDK and the
      # run died after that (a crash, a kill): the #10445 shape, not an infra hiccup. Otherwise it never got that far.
      if [[ $'\n'"$out"$'\n' == *$'\nSDK_BASH_DISPATCHED\n'* ]]; then
        if [[ "$exec_rc" == "137" || "$exec_rc" == "143" ]]; then
          # SIGKILL / SIGTERM after dispatch: the OOM killer, a container stop or a deploy signal, not a Bash result.
          SBV_VERDICT="smoke_infra_error"; SBV_REASON="probe_killed_rc_${exec_rc}${docker_err:+: $docker_err}"
        else
          SBV_VERDICT="sdk_bash_smoke_failed"; SBV_REASON="probe_rc_${exec_rc}_after_dispatch${docker_err:+: $docker_err}"
        fi
      elif [[ "$exec_rc" == "125" || "$exec_rc" == "126" || "$exec_rc" == "127" ]]; then
        SBV_VERDICT="smoke_infra_error"; SBV_REASON="docker_exec_rc_${exec_rc}${docker_err:+: $docker_err}"
      else
        SBV_VERDICT="smoke_infra_error"; SBV_REASON="probe_rc_${exec_rc}${docker_err:+: $docker_err}"
      fi ;;
  esac
}
